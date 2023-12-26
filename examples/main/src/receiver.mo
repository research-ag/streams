import Stream "../../../src/StreamReceiver";
import Buffer "mo:base/Buffer";
import Debug "mo:base/Debug";

actor Receiver {
  type ControlMessage = Stream.ControlMessage;
  type ChunkMessage = Stream.ChunkMessage<?Text>;

  let received = Buffer.Buffer<?Text>(0);

  stable let mem = Stream.new();
  let receiver = Stream.StreamReceiver<?Text>(
    mem,
    null,
    func(index : Nat, item : ?Text) {
      assert received.size() == index;
      received.add(item);
    },
  );

  public shared func receive(message : ChunkMessage) : async ControlMessage {
    receiver.onChunk(message);
  };

  public query func lastReceived() : async ??Text {
    if (received.size() == 0) { null } else {
      ?received.get(received.size() - 1);
    };
  };
};
