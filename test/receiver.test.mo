import StreamReceiver "../src/StreamReceiver";

do {
  var size = 0;
  func process(index : Nat, item : Text) {
    assert size == index;
    size += 1;
  };

  let receiver = StreamReceiver.StreamReceiver<Text>(0, null, process);

  assert receiver.onChunk((0, #chunk(["abc"]))) == #ok;
  assert receiver.onChunk((0, #chunk(["abc"]))) == #gap;
  assert receiver.onChunk((1, #chunk(["abc"]))) == #ok;
  assert receiver.onChunk((1, #chunk(["abc"]))) == #gap;
  assert receiver.onChunk((2, #chunk(["abc"]))) == #ok;
  assert receiver.onChunk((2, #chunk(["abc"]))) == #gap;
};

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
  assert receiver.onChunk((1, #chunk(["abc"]))) == #ok;
  assert receiver.lastChunkReceived() == 1;

  time := 2;
  assert receiver.onChunk((2, #ping)) == #ok;
  assert receiver.lastChunkReceived() == 2;

  time := 5;
  assert receiver.onChunk((2, #chunk(["abc"]))) == #stop;
};
