import Types "../src/types";

module StreamReceiver {
  public type Timeout = (Nat, () -> Int);
  public type ControlMessage = Types.ControlMessage;
  public type ChunkMessage<T> = Types.ChunkMessage<T>;

  public class StreamReceiver<T>(
    startPos : Nat,
    timeout : ?Timeout,
    itemCallback : (pos : Nat, item : T) -> (),
    // itemCallback is custom made per-stream and contains the streamId
  ) {

    var length_ : Nat = startPos;

    public func length() : Nat = length_;

    var lastChunkReceived_ : Int = switch (timeout) {
      case (?to) to.1 ();
      case (_) 0;
    };

    /// returns timestamp when stream received last chunk
    public func lastChunkReceived() : Int = lastChunkReceived_;

    /// returns flag if receiver timed out because of non-activity
    public func hasTimedOut() : Bool = switch (timeout) {
      case (?to)(to.1 () - lastChunkReceived_) > to.0;
      case (null) false;
    };

    /// processes a chunk and responds to sender
    public func onChunk(cm : Types.ChunkMessage<T>) : Types.ControlMessage {
      let (start, msg) = cm;
      if (start != length_) return #gap;
      if (hasTimedOut()) return #stop;
      switch (msg) {
        case (#chunk ch) {
          for (i in ch.keys()) {
            itemCallback(start + i, ch[i]);
          };
          length_ += ch.size();
        };
        case (#ping) {};
      };
      switch (timeout) {
        case (?to) lastChunkReceived_ := to.1 ();
        case (_) {};
      };
      return #ok;
    };
  };
};

// test index counter and gap detection
do {
  var size = 0;
  func process(index : Nat, item : Text) {
    assert size == index;
    size += 1;
  };

  let receiver = StreamReceiver.StreamReceiver<Text>(0, null, process);

  assert receiver.onChunk((0, #chunk(["abc"]))) == #ok;
  assert receiver.onChunk((0, #chunk(["abc"]))) == #gap;
  assert receiver.onChunk((0, #ping)) == #gap;
  assert receiver.onChunk((2, #chunk(["abc"]))) == #gap;
  assert receiver.onChunk((2, #ping)) == #gap;
  assert receiver.onChunk((1, #chunk(["abc", "abc"]))) == #ok;
  assert receiver.onChunk((1, #chunk(["abc"]))) == #gap;
  assert receiver.onChunk((2, #chunk(["abc"]))) == #gap;
  assert receiver.onChunk((4, #chunk(["abc"]))) == #gap;
  assert receiver.onChunk((3, #chunk(["abc"]))) == #ok;
};

// test timeout detection
do {
  var size = 0;
  func process(index : Nat, item : Text) {
    assert size == index;
    size += 1;
  };

  var time = 0;

  let receiver = StreamReceiver.StreamReceiver<Text>(0, ?(1, func() = time), process);
  assert receiver.onChunk((0, #chunk(["abc"]))) == #ok;
  assert receiver.lastChunkReceived() == 0;

  time := 1;
  assert receiver.onChunk((0, #chunk(["abc"]))) == #gap;
  assert receiver.lastChunkReceived() == 0;
  assert receiver.onChunk((1, #chunk(["abc"]))) == #ok;
  assert receiver.lastChunkReceived() == 1;

  time := 2;
  assert receiver.onChunk((2, #ping)) == #ok;
  assert receiver.lastChunkReceived() == 2;

  time := 4;
  assert receiver.onChunk((2, #chunk(["abc"]))) == #stop;
};
