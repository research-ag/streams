import StreamReceiver "../../../src/StreamReceiver";
import StreamSender "../../../src/StreamSender";
import Types "../../../src/types";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Debug "mo:base/Debug";

actor class Sender(receiverId : Principal) {
  let receiver = actor (Principal.toText(receiverId)) : actor {
    receive : (message : Types.ChunkMessage<?Text>) -> async Types.ControlMessage;
  };

  let MAX_LENGTH = 30;

  class counter() {
    var sum = 0;
    func wrap(item : Text) : (?Text, Nat) {
      let s = (to_candid (item)).size();
      if (s <= MAX_LENGTH) (?item, s) else (null, 0);
    };
    public func accept(item : Text) : ??Text {
      let (wrapped, size) = wrap(item);
      sum += size;
      if (sum <= MAX_LENGTH) ?wrapped else null;
    };
  };

  func send(message : Types.ChunkMessage<?Text>) : async* Types.ControlMessage {
    await receiver.receive(message);
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(
    counter,
    send,
    null
  );

  public shared func add(text : Text) : async () {
    Result.assertOk(sender.push(text));
  };

  system func heartbeat() : async() {
    await* sender.sendChunk();
  };
};
