import StreamReceiver "../../../src/StreamReceiver";
import StreamSender "../../../src/StreamSender";
import Types "../../../src/Types";
import Principal "mo:base/Principal";
import Result "mo:base/Result";

actor class Sender(receiverId : Principal) {
  let receiver = actor (Principal.toText(receiverId)) : actor {
    receive : (message : Types.ChunkMsg<?Text>) -> async Types.ControlMsg;
  };

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

  func send(message : Types.ChunkMsg<?Text>) : async* Types.ControlMsg {
    await receiver.receive(message);
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(
    counter,
    send,
    {
      maxQueueSize = null;
      maxConcurrentChunks = null;
      keepAliveSeconds = null;
    },
  );

  public shared func add(text : Text) : async () {
    Result.assertOk(sender.push(text));
  };

  system func heartbeat() : async() {
    assert (await* sender.sendChunk()) == #ok;
  };
};
