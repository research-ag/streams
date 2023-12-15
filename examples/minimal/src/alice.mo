import Stream "mo:streams/StreamSender";
import Principal "mo:base/Principal";

actor class Main(receiver : Principal) {
  // substitute your item type here
  type Item = Nat;

  // begin boilerplate
  type RecvFunc = shared Stream.ChunkMessage<Item> -> async Stream.ControlMessage;
  type ReceiverAPI = actor { receive : RecvFunc }; // substitute your receiver endpoint name
  let A : ReceiverAPI = actor (Principal.toText(receiver)); // use your receiver argument here
  let send_ = func(x : Stream.ChunkMessage<Item>) : async* Stream.ControlMessage {
    await A.receive(x) // ok to wrap custom code around this but not tamper with response
  };
  // end boilerplate

  // define your sender by defining counter
  class counter() {
    var sum = 0;
    let maxLength = 3;
    public func accept(item : Item) : ?Item {
      if (sum == maxLength) return null;
      sum += 1;
      return ?item;
    };
  };
  let sender = Stream.StreamSender<Item, Item>(counter, send_, null);

  // example use of sender `push` and `sendChunk`
  public shared func enqueue(n : Nat) : async () {
    var i = 0;
    while (i < n) {
      ignore sender.push((i + 1) ** 2);
      i += 1;
    };
  };
  
  public shared func batch() : async () {
    await* sender.sendChunk();
  };
};
