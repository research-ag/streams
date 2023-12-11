import StreamReceiver "../../../src/StreamReceiver";
import Buffer "mo:base/Buffer";
import Debug "mo:base/Debug";
import Types "../../../src/types";

actor class Receiver() {
  let received = Buffer.Buffer<?Text>(0);

  let receiver = StreamReceiver.StreamReceiver<?Text>(
    0,
    null,
    func(index : Nat, item : ?Text) {
      assert received.size() == index;
      received.add(item);
      Debug.print(debug_show item);
    },
  );

  public shared func receive(message : Types.ChunkMessage<?Text>) : async Types.ControlMessage {
    receiver.onChunk(message);
  };
};
