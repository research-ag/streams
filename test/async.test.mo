import AsyncMethodTester "mo:async";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Result "mo:base/Result";
import Nat32 "mo:base/Nat32";
import Debug "mo:base/Debug";
import Int "mo:base/Int";
import StreamSender "../src/StreamSender";
import StreamReceiver "../src/StreamReceiver";
import Base "sender.base";

let DEBUG = false;

type Item = (index : Nat, ?StreamSender.ControlMessage, StreamSender.Status, received : Nat, sent : Nat);

func test(sequence : [Item]) : async () {
  let n = sequence.size();

  let mock = AsyncMethodTester.ReleaseTester<StreamSender.ControlMessage>(DEBUG, ?"send", null);

  func sendChunkMessage(_ : StreamSender.ChunkMessage<?Text>) : async* StreamSender.ControlMessage {
    mock.call_result(await* mock.call());
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
    result[i] := async await* sender.sendChunk();
    await* mock.wait(i, #running);

    assert sender.status() == #ready and sender.received() == 0 and sender.sent() == i + 1;
  };

  for (item in sequence.vals()) {
    let (index, response, status, received, sent) = item;
    mock.release(index, response);
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

func allCases(n : Nat) : async () {
  func next_permutation(p : [var Nat]) : Bool {
    let n = p.size();

    func swap(i : Nat, j : Nat) {
      let x = p[i];
      p[i] := p[j];
      p[j] := x;
    };

    func reverse(from : Nat, to : Nat) {
      var a = from;
      var b = to;
      while (a < b) {
        swap(a, b);
        a += 1;
        b -= 1;
      };
    };

    var point : ?Nat = null;
    var i : Int = n - 2;
    label l while (i >= 0) {
      if (p[Int.abs(i)] < p[Int.abs(i + 1)]) {
        point := ?Int.abs(i);
        break l;
      };
      i -= 1;
    };
    switch (point) {
      case (null) {
        return false;
      };
      case (?x) {
        var i : Int = n - 1;
        label l while (i > x) {
          if (p[Int.abs(i)] > p[x]) {
            break l;
          };
          i -= 1;
        };
        swap(Int.abs(i), x);
        reverse(x + 1, n - 1);
      };
    };
    true;
  };

  type ChunkRequest = { #chunk; #ping };

  func getResponses(a_ : Nat32, b_ : Nat32, c : Nat) : ([(?StreamSender.ControlMessage, ChunkRequest)], Nat) {
    var time : Int = 0;
    let r = StreamReceiver.StreamReceiver<()>(
      func(pos : Nat, item : ()) = true,
      ?(1, func() = time),
    );
    var x = 0;
    let re = Array.tabulate<(?StreamSender.ControlMessage, ChunkRequest)>(
      n,
      func(i) {
        let resp = if (Nat32.bittest(a_, i)) {
          let m = if (Nat32.bittest(b_, i)) {
            #chunk([()]);
          } else {
            #ping;
          };
          ?r.onChunk(x, m);
        } else {
          null;
        };
        let req = if (Nat32.bittest(b_, i)) {
          x += 1;
          #chunk;
        } else {
          #ping;
        };
        if (c == i) {
          time := 100;
        };
        (resp, req);
      },
    );
    (re, r.length());
  };

  func test(p : [var Nat], responses : [(?StreamSender.ControlMessage, ChunkRequest)], len : Nat) : async Bool {
    var time = 0;

    let mock = AsyncMethodTester.ReleaseTester<StreamSender.ControlMessage>(DEBUG, ?"send", null);

    func sendChunkMessage(_ : StreamSender.ChunkMessage<?Text>) : async* StreamSender.ControlMessage {
      mock.call_result(await* mock.call());
    };

    let s = StreamSender.StreamSender<Text, ?Text>(
      sendChunkMessage,
      Base.create(1),
    );
    s.setKeepAlive(?(1, func() = time));
    s.setWindowSize(n + 1);

    var result = Array.init<async ()>(n, async ());

    for (i in Iter.range(0, n - 1)) {
      switch (responses[i].1) {
        case (#chunk) {
          Result.assertOk(s.push("a"));
        };
        case (#ping) {
          time := (i + 1) * 2;
        };
      };
      result[i] := async await* s.sendChunk();
      await* mock.wait(i, #running);
    };

    for (i in Iter.range(0, n - 1)) {
      mock.release(p[i], responses[p[i]].0);
      await result[p[i]];
    };
    s.status() != #shutdown and len == s.received();
  };

  let p = Array.tabulateVar<Nat>(n, func(i) = i);
  label l loop {
    for (i in Iter.range(0, 2 ** n - 1)) {
      for (j in Iter.range(0, 2 ** n - 1)) {
        for (time in Iter.range(0, n - 1)) {
          let a = Nat32.fromNat(i);
          let b = Nat32.fromNat(j);
          let (r, l) = getResponses(a, b, time);
          if (not (await test(p, r, l))) {
            Debug.print(debug_show (p, i, j, time, r));
            assert false;
          };
        };
      };
    };
    if (not next_permutation(p)) break l;
  };
};

do {
  for (i in Iter.range(2, 3)) {
    await allCases(i);
  };
};

type ItemA = ({ #send; #release : (Nat, ?StreamSender.ControlMessage) }, StreamSender.Status, Nat, Nat);

// The caller must ensure the sequence is correct.
// All chunks that get sent must be released or the test won't terminate.
func _test_arbitrary(sequence : [ItemA]) : async () {
  let n = Iter.size(Iter.filter(sequence.vals(), func(a : ItemA) : Bool = a.0 == #send));

  let mock = AsyncMethodTester.ReleaseTester<StreamSender.ControlMessage>(DEBUG, ?"send", null);

  func sendChunkMessage(_ : StreamSender.ChunkMessage<?Text>) : async* StreamSender.ControlMessage {
    mock.call_result(await* mock.call());
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(
    sendChunkMessage,
    Base.create(1),
  );

  for (i in Iter.range(0, n - 1)) {
    Result.assertOk(sender.push("a"));
  };

  var result = Array.init<async ()>(n, async ());
  var i = 0;
  for (item in sequence.vals()) {
    let (command, status, received, sent) = item;
    switch (command) {
      case (#send) {
        result[i] := async await* sender.sendChunk();
        await* mock.wait(i, #running);
        i += 1;
      };
      case (#release(j, response)) {
        mock.release(j, response);
        await result[j];
      };
    };
    assert sender.status() == status and sender.received() == received and sender.sent() == sent;
  };
};

// reach the #busy state
do {
  let N = StreamSender.MAX_CONCURRENT_CHUNKS_DEFAULT;

  let mock = AsyncMethodTester.ReleaseTester<StreamSender.ControlMessage>(DEBUG, ?"send", null);

  func sendChunkMessage(_ : StreamSender.ChunkMessage<?Text>) : async* StreamSender.ControlMessage {
    mock.call_result(await* mock.call());
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(
    sendChunkMessage,
    Base.create(1),
  );

  for (i in Iter.range(0, N - 1)) {
    Result.assertOk(sender.push("a"));
  };

  var result = Array.init<async ()>(N, async ());

  for (i in Iter.range(0, N - 2)) {
    result[i] := async await* sender.sendChunk();
    await* mock.wait(i, #running);
    assert sender.status() == #ready and sender.received() == 0 and sender.sent() == i + 1;
  };

  result[N - 1] := async await* sender.sendChunk();
  await* mock.wait(N - 1, #running);
  assert sender.status() == #busy and sender.received() == 0 and sender.sent() == N;

  for (i in Iter.range(0, N - 1)) {
    mock.release(i, ? #ok);
    await result[i];
    assert sender.status() == #ready and sender.received() == i + 1 and sender.sent() == N;
  };
};

// Test lost #ping
do {
  let n = 2;
  let mock = AsyncMethodTester.ReleaseTester<StreamSender.ControlMessage>(DEBUG, ?"send", null);

  func sendChunkMessage(_ : StreamSender.ChunkMessage<?Text>) : async* StreamSender.ControlMessage {
    mock.call_result(await* mock.call());
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(
    sendChunkMessage,
    Base.create(1),
  );
  var time = 0;
  sender.setKeepAlive(?(1, func() = time));

  var result = Array.init<async ()>(n, async ());

  time := 2;
  result[0] := async await* sender.sendChunk();
  await* mock.wait(0, #running);
  for (i in Iter.range(1, 3)) {
    Result.assertOk(sender.push("a"));
  };

  result[1] := async await* sender.sendChunk();
  await* mock.wait(1, #running);
  mock.release(1, ? #ok);
  await result[1];
  assert sender.status() == #ready and sender.received() == 1 and sender.sent() == 1;

  mock.release(0, null);
  await result[0];
  assert sender.status() == #ready and sender.received() == 1 and sender.sent() == 1;
};

// Test swb rotation
do {
  let mock = AsyncMethodTester.ReleaseTester<StreamSender.ControlMessage>(DEBUG, ?"send", null);

  func sendChunkMessage(_ : StreamSender.ChunkMessage<?Text>) : async* StreamSender.ControlMessage {
    mock.call_result(await* mock.call());
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(
    sendChunkMessage,
    Base.create(1),
  );

  for (i in Iter.range(1, 2)) {
    Result.assertOk(sender.push("a"));
  };

  let n = 4;
  var result = Array.init<async ()>(n, async ());

  result[0] := async await* sender.sendChunk();
  await* mock.wait(0, #running);

  result[1] := async await* sender.sendChunk();
  await* mock.wait(1, #running);

  mock.release(1, ? #ok);
  await result[1];
  assert sender.status() == #ready and sender.received() == 2 and sender.sent() == 2;

  Result.assertOk(sender.push("a"));

  result[2] := async await* sender.sendChunk();
  await* mock.wait(2, #running);

  mock.release(2, null);
  await result[2];
  assert sender.status() == #paused and sender.received() == 2 and sender.sent() == 2;

  mock.release(0, ? #ok);
  await result[0];
};
