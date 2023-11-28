import StreamReceiver "../src/StreamReceiver";
import StreamSender "../src/StreamSender";
import Buffer "mo:base/Buffer";
import Error "mo:base/Error";
import Option "mo:base/Option";

// types for receiver actor
type ChunkMsg = StreamReceiver.ChunkMsg<?Text>;
type ControlMsg = StreamReceiver.ControlMsg;

// receiver actor
actor B {
  // processor of received items
  let received = Buffer.Buffer<Text>(0);
  func processItem(_ : Nat, item : ?Text) {
    Option.iterate<Text>(item, func(x) = received.add(x));
  };

  // StreamReceiver
  let receiver = StreamReceiver.StreamReceiver<?Text>(
    0,
    null,
    processItem,
  );

  // required top-level boilerplate code,
  // a pass-through to StreamReceiver
  public func receive(cm : ChunkMsg) : async ControlMsg {
    // The failOn flag is used to simulate Errors.
    switch (mode) {
      case (#off) await* receiver.onChunk(cm);
      case (#reject) throw Error.reject("failOn");
      case (#stopped) return #stopped;
    };
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
  public func setFailMode(m : FailMode) {
    mode := m;
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
    await B.receive(m);
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
    sender.push(item);
  };

  public func trigger() : async () {
    await* sender.sendChunk();
  };
};


assert ((await A.submit("m0")) == #ok 0);
assert ((await A.submit("m1")) == #ok 1);
assert ((await A.submit("m2xxx")) == #ok 2);
assert ((await A.submit("m3-long")) == #ok 3);
assert ((await A.submit("m4-long")) == #ok 4);
assert ((await A.submit("m5")) == #ok 5);
assert ((await B.nReceived()) == 0);
await A.trigger(); // chunk m0, m1
assert ((await B.nReceived()) == 2);
B.setFailMode(#reject);
await A.trigger(); // chunk will fail
await A.trigger(); // chunk will fail
assert ((await B.nReceived()) == 2);
B.setFailMode(#off);
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
