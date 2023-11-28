import StreamReceiver "../src/StreamReceiver";
import StreamSender "../src/StreamSender";
import Buffer "mo:base/Buffer";
import Error "mo:base/Error";
import Option "mo:base/Option";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";

// types for receiver actor
type ChunkMsg = StreamReceiver.ChunkMsg<?Text>;
type ControlMsg = StreamReceiver.ControlMsg;

// receiver actor
actor B {
  // processor of received items
  let received = Buffer.Buffer<Text>(0);
  func processItem(i : Nat, item : ?Text) {
    let prefix = ".   B   item " # Nat.toText(i) # ": ";
    switch (item) {
      case (null) Debug.print(prefix # "null");
      case (?x) {
        Debug.print(prefix # x);
        received.add(x);
      };
    };
  };

  // StreamReceiver
  let receiver = StreamReceiver.StreamReceiver<?Text>(
    0,
    null,
    processItem,
  );

  // required top-level boilerplate code,
  // a pass-through to StreamReceiver
  public func receive(m : ChunkMsg) : async ControlMsg {
    let start = m.0;
    var end = m.0;
    var str = ".   B recv: (" # Nat.toText(m.0) # ", ";
    switch (m.1) {
      case (#ping) str #= "ping";
      case (#chunk e) {
        str #= "chunk [" # Nat.toText(e.size()) # "]";
        end := start + e.size();
      };
    };
    Debug.print(str # ")");
    str := ".   B reply: ";
    // The fail mode is used to simulate artifical Errors.
    let res = switch (mode) {
      case (#off) await* receiver.onChunk(m);
      case (#reject) {
        Debug.print(str # "reject");
        throw Error.reject("failMode");
      };
      case (#stopped) #stopped;
    };
    switch (res) {
      case (#ok) str #= "#ok";
      case (#stopped) str #= "#stopped";
    };
    Debug.print(str);
    res;
  };

  // query the items processor
  public query func listReceived() : async [Text] {
    Buffer.toArray(received);
  };
  public query func nReceived() : async Nat {
    received.size();
  };

  // simulate Errors
  type FailMode = { #off; #reject; #stopped };
  var mode : FailMode = #off;
  public func setFailMode(m : FailMode, n : Nat) : async () {
    if (n > 0) await setFailMode(m, n - 1) else {
      var str = ".   B failMode: ";
      switch (m) {
        case (#off) str #= "off";
        case (#stopped) str #= "stopped";
        case (#reject) str #= "reject";
      };
      Debug.print(str);
      mode := m;
    };
  };
};

// sender actor
// argument r is the receiver's shared receive function
actor A {
  let MAX_LENGTH = 5;

  class counter() {
    var sum = 0;
    // Any individual item larger than MAX_LENGTH is wrapped to null
    // and its size is not counted.
    func wrap(item : Text) : (?Text, Nat) {
      let s = item.size();
      if (s <= MAX_LENGTH) (?item, s) else (null, 0);
    };
    public func accept(item : Text) : ??Text {
      let (wrapped, size) = wrap(item);
      sum += size;
      if (sum <= MAX_LENGTH) ?wrapped else null;
    };
  };

  // Wrap the receiver's shared function.
  // This must always be done because we need to turn the receiver's shared
  // function into an async* return type.
  // We can place additional code here, for example, for logging.
  // However, we must not catch and convert any Errors. The Errors from
  // `await r` must be passed through unaltered or the StreamSender may break.
  func sendToReceiver(m : ChunkMsg) : async* ControlMsg {
    let start = m.0;
    var end = m.0;
    var str = "A send: (" # Nat.toText(m.0) # ", ";
    switch (m.1) {
      case (#ping) str #= "ping";
      case (#chunk e) {
        str #= "chunk [" # Nat.toText(e.size()) # "]";
        end := start + e.size();
      };
    };
    Debug.print(str # ")");
    str := "A recv: [" # Nat.toText(start) # "-" # Nat.toText(end) # ") ";
    try {
      let ret = await B.receive(m);
      switch (ret) {
        case (#ok) str #= "ok";
        case (#stopped) str #= "stopped";
      };
      Debug.print(str);
      return ret;
    } catch (e) {
      switch (Error.code(e)) {
        case (#canister_reject) str #= "reject(";
        case (#canister_error) str #= "trap(";
        case (_) str #= "other(";
      };
      str #= "\"" # Error.message(e) # "\")";
      Debug.print(str);
      throw e;
    };
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(
    counter,
    sendToReceiver,
    {
      maxQueueSize = null;
      maxConcurrentChunks = null;
      keepAliveSeconds = null;
    },
  );

  public func submit(item : Text) : async { #err : { #NoSpace }; #ok : Nat } {
    let res = sender.push(item);
    var str = "A submit: ";
    switch (res) {
      case (#ok i) str #= Nat.toText(i);
      case (#err e) str #= "NoSpace";
    };
    Debug.print(str);
    res;
  };

  var t = 0;
  public func trigger() : async () {
    let t_ = t;
    t += 1;
    Debug.print("A trigger: " # Nat.toText(t_) # " ");
    await* sender.sendChunk();
    // Debug.print("A trigger: " # Nat.toText(t_) # " <-");
  };
};

// Part 1: messages arrive and return one by one
Debug.print("=== Part 1 ===");
assert ((await A.submit("m0")) == #ok 0);
assert ((await A.submit("m1")) == #ok 1);
assert ((await A.submit("m2xxx")) == #ok 2);
assert ((await A.submit("m3-long")) == #ok 3);
assert ((await A.submit("m4-long")) == #ok 4);
assert ((await A.submit("m5")) == #ok 5);
assert ((await B.nReceived()) == 0);
await A.trigger(); // chunk m0, m1
assert ((await B.nReceived()) == 2);
await B.setFailMode(#reject, 0);
await A.trigger(); // chunk will fail
await A.trigger(); // chunk will fail
assert ((await B.nReceived()) == 2);
await B.setFailMode(#off, 0);
await A.trigger(); // chunk cdefg
assert ((await B.nReceived()) == 3);
await A.trigger(); // chunk null, null, fgh
assert ((await B.nReceived()) == 4);
await A.trigger(); // no items left
assert ((await B.nReceived()) == 4);
let list = await B.listReceived();
assert (list[0] == "m0");
assert (list[1] == "m1");
assert (list[2] == "m2xxx");
assert (list[3] == "m5");

// Part 2: second message sent out before first one returns
Debug.print("=== Part 2 ===");
assert ((await A.submit("m6xxx")) == #ok 6);
assert ((await A.submit("m7xxx")) == #ok 7);
ignore A.trigger();
ignore A.trigger();
await async {};
await async {};

// Part 3: test broken pipe behaviour
Debug.print("=== Part 3 ===");
assert ((await A.submit("m8")) == #ok 8);
assert ((await A.submit("m9")) == #ok 9);
assert ((await A.submit("mA")) == #ok 10);
assert ((await A.submit("mB")) == #ok 11);
ignore B.setFailMode(#reject, 0);
ignore A.trigger();
ignore B.setFailMode(#off, 1);
ignore A.trigger();
await async {};
ignore A.trigger();
ignore A.trigger();
