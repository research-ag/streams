import StreamSender "../src/StreamSender";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Iter "mo:base/Iter";
import Array "mo:base/Array";
import Base "sender.base";
// Note: A chunk response of #trap (aka canister_error) cannot be simulated with
// the moc interpreter. Calling Debug.trap() to generate the error would
// instantly terminate the whole test.
type ChunkResponse = { #ok; #gap; #stop; #reject };

class Chunk() {
  var response : ?ChunkResponse = null;

  public func run() : async StreamSender.ControlMessage {
    while (response == null) await async {};
    switch (response) {
      case (? #ok) #ok;
      case (? #gap) #gap;
      case (? #stop) #stop;
      case (? #reject) throw Error.reject("");
      case (null) Debug.trap("cannot happen");
    };
  };

  public func release(result : ChunkResponse) {
    assert response == null;
    response := ?result;
  };
};

class Sender(n : Nat) {
  var chunkRegister : Chunk = Chunk();
  var correct = true;

  func sendChunkMessage(message : StreamSender.ChunkMessage<?Text>) : async* StreamSender.ControlMessage {
    let chunk = chunkRegister;
    await chunk.run();
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(
    Base.create(1),
    sendChunkMessage,
    null,
  );

  public func send(chunk : Chunk) : async () {
    chunkRegister := chunk;
    await* sender.sendChunk();
  };

  public func expect(st : StreamSender.Status, received : Nat, sent : Nat) : () {
    let cond = sender.status() == st and sender.received() == received and sender.sent() == sent;
    //Debug.print(debug_show (sender.status(), sender.received(), sender.sent()));
    if (not cond) correct := false;
  };

  public func assert_() {
    assert correct;
  };

  for (i in Iter.range(1, n)) {
    Result.assertOk(sender.push("a"));
  };
};

// Note: We cannot pass futures across contexts, neither as arguments to
// functions nor return them from functions. We cannot read or write the
// global result[] array from within a function either. That's why it is hard to
// shorten the commands below with any kind of convenience function.

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
    (#gap, #ready, 0, 0),
    (#reject, #ready, 0, 0),
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
    (#reject, #stopped, 0, 0),
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
await test([
  (0, #ok, #ready, 1, 2),
  (1, #ok, #ready, 2, 2),
]);

await test([
  (0, #stop, #stopped, 0, 0),
  (1, #ok, #shutdown, 2, 0),
]);

await test([
  (0, #gap, #paused, 0, 0),
  (1, #gap, #ready, 0, 0),
]);

await test([
  (0, #reject, #paused, 0, 0),
  (1, #gap, #ready, 0, 0),
]);

// two concurrent chunks respond in reverse order
do {
  let tests = [
    ([#ok, #ok], [(#ready, 2, 2), (#ready, 2, 2)]),
    ([#ok, #gap], [(#paused, 0, 1), (#ready, 1, 1)]),
    ([#ok, #reject], [(#paused, 0, 1), (#ready, 1, 1)]),
    ([#ok, #stop], [(#stopped, 1, 1), (#stopped, 1, 1)]),

    ([#gap, #ok], [(#ready, 2, 2), (#shutdown, 2, 0)]),
    ([#gap, #gap], [(#paused, 0, 1), (#ready, 0, 0)]),
    ([#gap, #reject], [(#paused, 0, 1), (#ready, 0, 0)]),
    ([#gap, #stop], [(#stopped, 1, 1), (#shutdown, 1, 0)]),
    
    ([#reject, #ok], [(#ready, 2, 2), (#shutdown, 2, 0)]),
    ([#reject, #gap], [(#paused, 0, 1), (#ready, 0, 0)]),
    ([#reject, #reject], [(#paused, 0, 1), (#ready, 0, 0)]),
    ([#reject, #stop], [(#stopped, 1, 1), (#shutdown, 1, 0)]),
    
    ([#stop, #ok], [(#ready, 2, 2), (#shutdown, 2, 0)]),
    ([#stop, #gap], [(#paused, 0, 1), (#stopped, 0, 0)]),
    ([#stop, #reject], [(#paused, 0, 1), (#stopped, 0, 0)]),
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
