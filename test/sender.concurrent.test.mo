import StreamSender "../src/StreamSender";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Iter "mo:base/Iter";
import Array "mo:base/Array";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Random "mo:base/Random";
import Option "mo:base/Option";
import Base "sender.base";
import StreamReceiver "../src/StreamReceiver";
// Note: A chunk response of #trap (aka canister_error) cannot be simulated with
// the moc interpreter. Calling Debug.trap() to generate the error would
// instantly terminate the whole test.
type ChunkResponse = { #ok; #gap; #stop; #error };

class Chunk() {
  var response : ?ChunkResponse = null;

  public func run() : async StreamSender.ControlMessage {
    while (response == null) await async {};
    switch (response) {
      case (? #ok) #ok;
      case (? #gap) #gap;
      case (? #stop) #stop;
      case (? #error) throw Error.reject("");
      case (null) Debug.trap("cannot happen");
    };
  };

  public func release(result : ChunkResponse) {
    assert response == null;
    response := ?result;
  };
};

// Note: We cannot pass futures across contexts, neither as arguments to
// functions nor return them from functions. We cannot read or write the
// global result[] array from within a function either. That's why it is hard to
// shorten the commands below with any kind of convenience function.

class Sender(n : Nat) {
  var chunkRegister : Chunk = Chunk();
  var correct = true;
  var time = 0;

  func sendChunkMessage(message : StreamSender.ChunkMessage<?Text>) : async* StreamSender.ControlMessage {
    let chunk = chunkRegister;
    // Debug.print(debug_show message);
    await chunk.run();
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(
    sendChunkMessage,
    Base.create(1)
  );
  sender.setKeepAlive(?(1, func() = time));

  public func send(chunk : Chunk) : async () {
    chunkRegister := chunk;
    await* sender.sendChunk();
  };

  public func expect(st : StreamSender.Status, received : Nat, sent : Nat) : () {
    let cond = sender.status() == st and sender.received() == received and sender.sent() == sent;
    // Debug.print(debug_show (sender.status(), sender.received(), sender.sent()));
    if (not cond) correct := false;
  };

  public func assert_() {
    assert correct;
  };

  public func push(n : Nat) {
    for (i in Iter.range(1, n)) {
      Result.assertOk(sender.push("a"));
    };
  };

  public func setTime(t : Nat) {
    time := t;
  };

  public func setMaxN(n : Nat) {
    sender.setWindowSize(n);
  };

  public func status() : StreamSender.Status = sender.status();

  public func received() : Nat = sender.received();

  push(n);
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

  func getResponses(a_ : Nat32, b_ : Nat32, c : Nat) : ([(ChunkResponse, ChunkRequest)], Nat) {
    var time : Int = 0;
    let r = StreamReceiver.StreamReceiver<()>(
      func(pos : Nat, item : ()) = (),
      ?(1, func() = time),
    );
    var x = 0;
    let re = Array.tabulate<(ChunkResponse, ChunkRequest)>(
      n,
      func(i) {
        let resp = if (Nat32.bittest(a_, i)) {
          let m = if (Nat32.bittest(b_, i)) {
            #chunk([()]);
          } else {
            #ping;
          };
          r.onChunk(x, m);
        } else {
          #error;
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

  func test(p : [var Nat], responses : [(ChunkResponse, ChunkRequest)], len : Nat) : async Bool {
    let s = Sender(0);
    s.setMaxN(n + 1);

    let chunk = Array.tabulate<Chunk>(n, func(i) = Chunk());
    var result = Array.init<async ()>(n, async ());

    for (i in Iter.range(0, n - 1)) {
      switch (responses[i].1) {
        case (#chunk) {
          s.push(1);
        };
        case (#ping) {
          s.setTime((i + 1) * 2);
        };
      };
      result[i] := s.send(chunk[i]);
      await async {};
    };

    for (i in Iter.range(0, n - 1)) {
      chunk[p[i]].release(responses[p[i]].0);
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

// randomized max test
do {
  class RNG() {
    var seed = 0;

    public func next() : Nat {
      seed += 29;
      let a = seed * 15485863;
      a * a * a % 2038074743;
    };
  };

  func random_permutation(n : Nat) : [var Nat] {
    let p = Array.thaw<Nat>(Iter.toArray(Iter.range(0, n - 1)));
    let rng = RNG();
    for (ii in Iter.revRange(n - 1, 0)) {
      let i = Int.abs(ii);
      let j = rng.next() % n;
      let x = p[i];
      p[i] := p[j];
      p[j] := x;
    };

    p;
  };

  let n = 100;
  let p = random_permutation(n);
  let s = Sender(n);
  let r = StreamReceiver.StreamReceiver<()>(func(pos : Nat, item : ()) = (), null);

  s.setMaxN(n + 1);
  let chunk = Array.tabulate<Chunk>(n, func(i) = Chunk());
  var result = Array.init<async ()>(n, async ());

  for (i in Iter.range(0, n - 1)) {
    result[i] := s.send(chunk[i]);
    await async {};
    s.expect(#ready, 0, i + 1);
  };

  var max = 0;
  for (index in p.vals()) {
    let response = r.onChunk(index, #chunk([()]));
    chunk[index].release(response);
    await result[index];
  };
  assert s.status() == #ready;
};

type ItemA = ({ #send; #release : (Nat, ChunkResponse) }, StreamSender.Status, Nat, Nat);

// The caller must ensure the sequence is correct.
// All chunks that get sent must be released or the test won't terminate.
func test_arbitrary(sequence : [ItemA]) : async () {
  let n = Iter.size(Iter.filter(sequence.vals(), func(a : ItemA) : Bool = a.0 == #send));

  let s = Sender(n);

  let chunk = Array.tabulate<Chunk>(n, func(i) = Chunk());
  var result = Array.init<async ()>(n, async ());
  var i = 0;
  for (item in sequence.vals()) {
    let (command, status, received, sent) = item;
    switch (command) {
      case (#send) {
        result[i] := s.send(chunk[i]);
        await async {};
        i += 1;
      };
      case (#release(j, response)) {
        chunk[j].release(response);
        await result[j];
      };
    };
    s.expect(status, received, sent);
  };
  s.assert_();
};

type Item = (index : Nat, ChunkResponse, StreamSender.Status, received : Nat, sent : Nat);

// With this function tests all sends happen first.
// Then responses can be released in arbitrary order.
// The caller must still ensure the sequence is correct.
// All chunks that get sent must be released or the test won't terminate.
func test(sequence : [Item]) : async () {
  let n = sequence.size();
  let s = Sender(n);

  let chunk = Array.tabulate<Chunk>(n, func(i) = Chunk());
  var result = Array.init<async ()>(n, async ());

  for (i in Iter.range(0, n - 1)) {
    result[i] := s.send(chunk[i]);
    await async {};
    s.expect(#ready, 0, i + 1);
  };

  for (item in sequence.vals()) {
    let (index, response, status, received, sent) = item;
    chunk[index].release(response);
    await result[index];
    s.expect(status, received, sent);
  };
  s.assert_();
};

// single chunk starting from the #ready state
do {
  let tests = [
    (#ok, #ready, 1, 1),
    (#gap, #shutdown, 0, 0),
    (#error, #ready, 0, 0),
    (#stop, #stopped, 0, 0),
  ];
  for (t in tests.vals()) {
    let (response, status, pos, sent) = t;
    await test([(0, response, status, pos, sent)]);
  };
};

// single chunk starting from the #stopped state
do {
  let tests = [
    (#ok, #shutdown, 2, 0),
    (#gap, #stopped, 0, 0),
    (#error, #stopped, 0, 0),
    (#stop, #shutdown, 1, 0),
  ];
  for (t in tests.vals()) {
    let (response, status, pos, sent) = t;
    await test([
      (0, #stop, #stopped, 0, 0),
      (1, response, status, pos, sent),
    ]);
  };
};

// two concurrent chunks respond in order
do {
  let tests = [
    ([#ok, #ok], [(#ready, 1, 2), (#ready, 2, 2)]),
    ([#ok, #gap], [(#ready, 1, 2), (#shutdown, 1, 1)]),
    ([#ok, #error], [(#ready, 1, 2), (#ready, 1, 1)]),
    ([#ok, #stop], [(#ready, 1, 2), (#stopped, 1, 1)]),

    ([#gap, #ok], [(#shutdown, 0, 0), (#shutdown, 2, 0)]),
    ([#gap, #gap], [(#shutdown, 0, 0), (#shutdown, 0, 0)]),
    ([#gap, #error], [(#shutdown, 0, 0), (#shutdown, 0, 0)]),
    ([#gap, #stop], [(#shutdown, 0, 0), (#shutdown, 1, 0)]),

    ([#error, #ok], [(#paused, 0, 0), (#shutdown, 2, 0)]),
    ([#error, #gap], [(#paused, 0, 0), (#ready, 0, 0)]),
    ([#error, #error], [(#paused, 0, 0), (#ready, 0, 0)]),
    ([#error, #stop], [(#paused, 0, 0), (#shutdown, 1, 0)]),

    ([#stop, #ok], [(#stopped, 0, 0), (#shutdown, 2, 0)]),
    ([#stop, #gap], [(#stopped, 0, 0), (#stopped, 0, 0)]),
    ([#stop, #error], [(#stopped, 0, 0), (#stopped, 0, 0)]),
    ([#stop, #stop], [(#stopped, 0, 0), (#shutdown, 1, 0)]),
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
    ([#ok, #ok], [(#ready, 2, 2), (#ready, 2, 2)]),
    ([#ok, #gap], [(#paused, 0, 1), (#ready, 1, 1)]),
    ([#ok, #error], [(#paused, 0, 1), (#ready, 1, 1)]),
    ([#ok, #stop], [(#stopped, 1, 1), (#stopped, 1, 1)]),

    ([#gap, #ok], [(#ready, 2, 2), (#shutdown, 2, 0)]),
    ([#gap, #gap], [(#paused, 0, 1), (#shutdown, 0, 0)]),
    ([#gap, #error], [(#paused, 0, 1), (#shutdown, 0, 0)]),
    ([#gap, #stop], [(#stopped, 1, 1), (#shutdown, 1, 0)]),

    ([#error, #ok], [(#ready, 2, 2), (#shutdown, 2, 0)]),
    ([#error, #gap], [(#paused, 0, 1), (#ready, 0, 0)]),
    ([#error, #error], [(#paused, 0, 1), (#ready, 0, 0)]),
    ([#error, #stop], [(#stopped, 1, 1), (#shutdown, 1, 0)]),

    ([#stop, #ok], [(#ready, 2, 2), (#shutdown, 2, 0)]),
    ([#stop, #gap], [(#paused, 0, 1), (#stopped, 0, 0)]),
    ([#stop, #error], [(#paused, 0, 1), (#stopped, 0, 0)]),
    ([#stop, #stop], [(#stopped, 1, 1), (#shutdown, 1, 0)]),
  ];
  for (t in tests.vals()) {
    let (responses, statuses) = t;
    await test([
      (1, responses[1], statuses[0].0, statuses[0].1, statuses[0].2),
      (0, responses[0], statuses[1].0, statuses[1].1, statuses[1].2),
    ]);
  };
};

// reach the #busy state
do {
  let N = StreamSender.MAX_CONCURRENT_CHUNKS_DEFAULT;
  let s = Sender(N);
  let chunk = Array.tabulate<Chunk>(N, func(i) = Chunk());
  var result = Array.init<async ()>(chunk.size(), async ());

  for (i in Iter.range(0, N - 2)) {
    result[i] := s.send(chunk[i]);
    await async {};
    s.expect(#ready, 0, i + 1);
  };

  result[N - 1] := s.send(chunk[N - 1]);
  await async {};
  s.expect(#busy, 0, N);

  for (i in Iter.range(0, N - 1)) {
    chunk[i].release(#ok);
    await result[i];
    s.expect(#ready, i + 1, N);
  };

  s.assert_();
};

// Test lost #ping
do {
  let n = 2;
  let s = Sender(0);

  let chunk = Array.tabulate<Chunk>(n, func(i) = Chunk());
  var result = Array.init<async ()>(n, async ());

  s.setTime(2);
  result[0] := s.send(chunk[0]);
  await async {};

  s.push(3);
  result[1] := s.send(chunk[1]);
  chunk[1].release(#ok);
  await result[1];
  s.expect(#ready, 1, 1);

  chunk[0].release(#error);
  await result[0];
  s.expect(#ready, 1, 1);

  s.assert_();
};

// Test swb rotation
do {
  let s = Sender(2);

  let n = 4;
  let chunk = Array.tabulate<Chunk>(n, func(i) = Chunk());
  var result = Array.init<async ()>(n, async ());

  result[0] := s.send(chunk[0]);
  result[1] := s.send(chunk[1]);
  chunk[1].release(#ok);
  await result[1];
  s.expect(#ready, 2, 2);
  s.push(1);
  result[2] := s.send(chunk[2]);
  chunk[2].release(#error);
  await result[2];
  s.expect(#ready, 2, 2);
  chunk[0].release(#ok);
  await result[0];
};
