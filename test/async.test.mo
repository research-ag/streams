import AsyncMethodTester "mo:mrr/AsyncMethodTester";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Result "mo:base/Result";
import StreamSender "../src/StreamSender";
import Base "sender.base";

type Item = (index : Nat, ?StreamSender.ControlMessage, StreamSender.Status, received : Nat, sent : Nat);

func test(sequence : [Item]) : async () {
  let n = sequence.size();

  let mock = AsyncMethodTester.AsyncMethodTester<StreamSender.ChunkMessage<?Text>, (), StreamSender.ControlMessage>(null);

  func sendChunkMessage(message : StreamSender.ChunkMessage<?Text>) : async* StreamSender.ControlMessage {
    await* mock.call(message, null);
    mock.call_result();
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(
    sendChunkMessage,
    Base.create(1),
  );

  for (i in Iter.range(0, n - 1)) {
    Result.assertOk(sender.push("a"));
  };

  var result = Array.init<async ()>(n, async ());

  for (i in Iter.range(0, n - 1)) {
    result[i] := async {
      await* sender.sendChunk();
    };
    await async ();

    assert sender.status() == #ready and sender.received() == 0 and sender.sent() == i + 1;
  };

  for (item in sequence.vals()) {
    let (index, response, status, received, sent) = item;
    mock.release(index, ?response);
    await result[index];
    assert sender.status() == status and sender.received() == received and sender.sent() == sent;
  };
};

// single chunk starting from the #ready state
do {
  let tests = [
    (? #ok, #ready, 1, 1),
    (? #gap, #shutdown, 0, 0),
    (null, #ready, 0, 0),
    (? #stop 0, #stopped, 0, 0),
  ];
  for (t in tests.vals()) {
    let (response, status, pos, sent) = t;
    await test([(0, response, status, pos, sent)]);
  };
};

// single chunk starting from the #stopped state
do {
  let tests = [
    (? #ok, #shutdown, 2, 0),
    (? #gap, #stopped, 0, 0),
    (null, #stopped, 0, 0),
    (? #stop 0, #shutdown, 1, 0),
  ];
  for (t in tests.vals()) {
    let (response, status, pos, sent) = t;
    await test([
      (0, ? #stop 0, #stopped, 0, 0),
      (1, response, status, pos, sent),
    ]);
  };
};

// two concurrent chunks respond in order
do {
  let tests = [
    ([? #ok, ? #ok], [(#ready, 1, 2), (#ready, 2, 2)]),
    ([? #ok, ? #gap], [(#ready, 1, 2), (#shutdown, 1, 1)]),
    ([? #ok, null], [(#ready, 1, 2), (#ready, 1, 1)]),
    ([? #ok, ? #stop 0], [(#ready, 1, 2), (#stopped, 1, 1)]),

    ([? #gap, ? #ok], [(#shutdown, 0, 0), (#shutdown, 2, 0)]),
    ([? #gap, ? #gap], [(#shutdown, 0, 0), (#shutdown, 0, 0)]),
    ([? #gap, null], [(#shutdown, 0, 0), (#shutdown, 0, 0)]),
    ([? #gap, ? #stop 0], [(#shutdown, 0, 0), (#shutdown, 1, 0)]),

    ([null, ? #ok], [(#paused, 0, 0), (#shutdown, 2, 0)]),
    ([null, ? #gap], [(#paused, 0, 0), (#ready, 0, 0)]),
    ([null, null], [(#paused, 0, 0), (#ready, 0, 0)]),
    ([null, ? #stop 0], [(#paused, 0, 0), (#shutdown, 1, 0)]),

    ([? #stop 0, ? #ok], [(#stopped, 0, 0), (#shutdown, 2, 0)]),
    ([? #stop 0, ? #gap], [(#stopped, 0, 0), (#stopped, 0, 0)]),
    ([? #stop 0, null], [(#stopped, 0, 0), (#stopped, 0, 0)]),
    ([? #stop 0, ? #stop 0], [(#stopped, 0, 0), (#shutdown, 1, 0)]),
  ];
  for (t in tests.vals()) {
    let (responses, statuses) = t;
    await test([
      (0, responses[0], statuses[0].0, statuses[0].1, statuses[0].2),
      (1, responses[1], statuses[1].0, statuses[1].1, statuses[1].2),
    ]);
  };
};

// two concurrent chunks respond in reverse order
do {
  let tests = [
    ([? #ok, ? #ok], [(#ready, 2, 2), (#ready, 2, 2)]),
    ([? #ok, ? #gap], [(#paused, 0, 1), (#ready, 1, 1)]),
    ([? #ok, null], [(#paused, 0, 1), (#ready, 1, 1)]),
    ([? #ok, ? #stop 0], [(#stopped, 1, 1), (#stopped, 1, 1)]),

    ([? #gap, ? #ok], [(#ready, 2, 2), (#shutdown, 2, 0)]),
    ([? #gap, ? #gap], [(#paused, 0, 1), (#shutdown, 0, 0)]),
    ([? #gap, null], [(#paused, 0, 1), (#shutdown, 0, 0)]),
    ([? #gap, ? #stop 0], [(#stopped, 1, 1), (#shutdown, 1, 0)]),

    ([null, ? #ok], [(#ready, 2, 2), (#shutdown, 2, 0)]),
    ([null, ? #gap], [(#paused, 0, 1), (#ready, 0, 0)]),
    ([null, null], [(#paused, 0, 1), (#ready, 0, 0)]),
    ([null, ? #stop 0], [(#stopped, 1, 1), (#shutdown, 1, 0)]),

    ([? #stop 0, ? #ok], [(#ready, 2, 2), (#shutdown, 2, 0)]),
    ([? #stop 0, ? #gap], [(#paused, 0, 1), (#stopped, 0, 0)]),
    ([? #stop 0, null], [(#paused, 0, 1), (#stopped, 0, 0)]),
    ([? #stop 0, ? #stop 0], [(#stopped, 1, 1), (#shutdown, 1, 0)]),
  ];
  for (t in tests.vals()) {
    let (responses, statuses) = t;
    await test([
      (1, responses[1], statuses[0].0, statuses[0].1, statuses[0].2),
      (0, responses[0], statuses[1].0, statuses[1].1, statuses[1].2),
    ]);
  };
};
