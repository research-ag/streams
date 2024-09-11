import StreamReceiver "../src/StreamReceiver";

// test index counter and gap detection
do {
  var size = 0;
  func process(index : Nat, _ : Text) : Bool {
    size += 1;
    size == index + 1;
  };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);

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
  func process(index : Nat, _ : Text) : Bool {
    size += 1;
    size == index + 1;
  };

  var time = 0;

  let receiver = StreamReceiver.StreamReceiver<Text>(process, ?(1, func() = time));
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
  assert receiver.onChunk((2, #chunk(["abc"]))) == #stop 0;
};
