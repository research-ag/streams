import StreamReceiver "../src/StreamReceiver";
import StreamSender "../src/StreamSender";
import Buffer "mo:base/Buffer";
import Error "mo:base/Error";
import Option "mo:base/Option";

// types for sender actor
type ChunkMsg = StreamSender.ChunkMsg<?Text>;
type ControlMsg = StreamSender.ControlMsg;
type ReceiveFunc = shared (ChunkMsg) -> async StreamSender.ControlMsg;

// sender actor
// argument r is the receiver's shared receive function
actor class Alice(r : ReceiveFunc) {
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
    await r(m);
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

// types for sender actor
// type ChunkMsg = StreamReceiver.ChunkMsg<?Text>;
// type ControlMsg = StreamReceiver.ControlMsg;
// type ReceiveFunc = shared (Chunk) -> async StreamReceiver.ControlMsg;

// receiver actor
actor class Bob() {
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

let b = await Bob(); // create receiver
let a = await Alice(b.receive); // create sender
assert ((await a.submit("ab")) == #ok 0);
assert ((await a.submit("bcd")) == #ok 1);
assert ((await a.submit("cdefg")) == #ok 2);
assert ((await a.submit("defghi")) == #ok 3);
assert ((await a.submit("efghij")) == #ok 4);
assert ((await a.submit("fgh")) == #ok 5);
assert ((await b.nReceived()) == 0);
await a.trigger(); // chunk ab, bcd
assert ((await b.nReceived()) == 2);
b.setFailMode(#reject);
await a.trigger(); // chunk will fail
await a.trigger(); // chunk will fail
assert ((await b.nReceived()) == 2);
b.setFailMode(#off);
await a.trigger(); // chunk cdefg
assert ((await b.nReceived()) == 3);
await a.trigger(); // chunk null, null, fgh
assert ((await b.nReceived()) == 4);
await a.trigger(); // no items left
assert ((await b.nReceived()) == 4);
let list = await b.listReceived();
assert (list[0] == "ab");
assert (list[1] == "bcd");
assert (list[2] == "cdefg");
assert (list[3] == "fgh");
