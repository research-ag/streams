import StreamReceiver "../src/StreamReceiver";
import StreamSender "../src/StreamSender";
import Buffer "mo:base/Buffer";
import Error "mo:base/Error";
import Option "mo:base/Option";

type Receiver = actor { receive : ([?Text], Nat) -> async Bool };

// sender actor
actor class A(r : Receiver) {
  let MAX_LENGTH = 5;

  class counter() {
    var sum = 0;
    public func accept(item : Text) : Bool {
      sum += item.size();
      sum <= MAX_LENGTH;
    };
  };

  func wrap(item : Text) : ?Text {
    if (item.size() <= MAX_LENGTH) { ?item } else { null };
  };

  func sendToReceiver(items : [?Text], start : Nat) : async* Bool {
    await r.receive(items, start);
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

actor class B() {
  // processor 
  let received = Buffer.Buffer<Text>(0);
  func process(item : ?Text, _ : Nat) {
    Option.iterate<Text>(item, func(x) = received.add(x));
  };

  // receiver
  let receiver = StreamReceiver.StreamReceiver<?Text>(
    0,
    null,
    process,
  );

  // pass-through to receiver
  public func receive(items : [?Text], index : Nat) : async Bool {
    await* receiver.onChunk(items, index);
  };
 
  // pass-through to processor
  public query func listReceived() : async [Text] {
    Buffer.toArray(received);
  };
  public query func nReceived() : async Nat {
    received.size();
  };
};

let b = await B(); // create receiver B
let a = await A(b); // create sender A
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
await a.trigger(); // 6 chars won't go through
assert ((await b.nReceived()) == 3);
await a.trigger(); // sender will be stuck, the 6 char item will never be popped
assert ((await b.nReceived()) == 3);
let list = await b.listReceived();
assert (list[0] == "ab");
assert (list[1] == "bcd");
assert (list[2] == "cdefg");
