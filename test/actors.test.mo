import StreamReceiver "../src/StreamReceiver";
import StreamSender "../src/StreamSender";
import Buffer "mo:base/Buffer";
import Error "mo:base/Error";
import Option "mo:base/Option";

type Chunk = StreamSender.Chunk<?Text>;
// or type Chunk = StreamReceiver.Chunk<?Text>;
type ReceiveFunc = shared (Chunk) -> async Bool;

// sender actor
// argument r is the receiver's shared receive function
actor class A(r : ReceiveFunc) {
  let MAX_LENGTH = 5;

  class counter() {
    var sum = 0;
    public func accept(item : Text) : Bool {
      // the wrap function replaces too large items with null
      if (item.size() > MAX_LENGTH) return true;
      sum += item.size();
      sum <= MAX_LENGTH;
    };
  };

  func wrap(item : Text) : ?Text {
    if (item.size() <= MAX_LENGTH) { ?item } else { null };
  };

  // Wrap the receiver's shared function.
  // This must always be done because we need to turn the receiver's shared
  // function into an async* return type.
  // We can place additional code here, for example, for logging.
  // However, we must not catch and convert any Errors. The Errors from
  // `await r` must be passed through unaltered or the StreamSender may break. 
  func sendToReceiver(ch : Chunk) : async* Bool {
    await r(ch);
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(
    counter,
    wrap,
    sendToReceiver,
    {
      maxQueueSize = null;
      maxConcurrentChunks = null;
      keepAliveSeconds = null;
    },
  );

  public func queue(item : Text) : async { #err : { #NoSpace }; #ok : Nat } {
    sender.add(item);
  };

  public func trigger() : async () {
    await* sender.sendChunk();
  };
};

// receiver actor
actor class B() {
  // processor of received items 
  let received = Buffer.Buffer<Text>(0);
  func processItem(item : ?Text, _ : Nat) {
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
  public func receive(ch : Chunk) : async Bool {
    await* receiver.onChunk(ch);
  };
 
  // query the items processor
  public query func listReceived() : async [Text] {
    Buffer.toArray(received);
  };
  public query func nReceived() : async Nat {
    received.size();
  };
};

let b = await B(); // create receiver B
let a = await A(b.receive); // create sender A
assert ((await a.queue("ab")) == #ok 0);
assert ((await a.queue("bcd")) == #ok 1);
assert ((await a.queue("cdefg")) == #ok 2);
assert ((await a.queue("defghi")) == #ok 3);
assert ((await a.queue("efg")) == #ok 4);
assert ((await b.nReceived()) == 0);
await a.trigger();
assert ((await b.nReceived()) == 2);
await a.trigger();
assert ((await b.nReceived()) == 3);
await a.trigger(); // 6 char item will be skipped
assert ((await b.nReceived()) == 4);
await a.trigger(); // no new items
assert ((await b.nReceived()) == 4);
let list = await b.listReceived();
assert (list[0] == "ab");
assert (list[1] == "bcd");
assert (list[2] == "cdefg");
assert (list[3] == "efg");
