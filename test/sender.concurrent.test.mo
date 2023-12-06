import StreamSender "../src/StreamSender";
import Types "../src/types";
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

  public func run() : async Types.ControlMsg {
    while (response == null) await async {};
    switch (response) {
      case (? #ok) #ok;
      case (? #gap) #gap;
      case (? #stop) #stop;
      case (? #reject) throw Error.reject("");
      case (null) Debug.trap("cannot happen");
    };
  };

  public func release(result : ChunkResponse) = response := ?result;
};

class Sender() {
  var chunkRegister : Chunk = Chunk();
  var correct = true;

  func sendChunkMsg(message : Types.ChunkMsg<?Text>) : async* Types.ControlMsg {
    let chunk = chunkRegister;
    await chunk.run();
  };
  let sender = StreamSender.StreamSender<Text, ?Text>(
    Base.create(5),
    sendChunkMsg,
    {
      maxQueueSize = null;
      maxConcurrentChunks = null;
      keepAliveSeconds = null;
    },
  );

  public func send(chunk : Chunk) : async () {
    chunkRegister := chunk;
    await* sender.sendChunk();
  };

  public func expect(st : StreamSender.Status, pos : Nat) : () {
    let cond = sender.status() == st and sender.received() == pos;
    Debug.print(debug_show (sender.status(), sender.received()));
    if (not cond) correct := false;
  };

  public func assert_() {
    assert correct;
  };

  for (i in Iter.range(1, 10)) {
    Result.assertOk(sender.push("abc"));
  };
};

// Note: We cannot pass futures across contexts, neither as arguments to
// functions nor return them from functions. We cannot read or write the
// global result[] array from within a function either. That's why it is hard to
// shorten the commands below with any kind of convenience function.

do {
  let s = Sender();
  let chunk = Array.tabulate<Chunk>(2, func(i) = Chunk());
  var result = Array.init<async ()>(chunk.size(), async ());

  result[0] := s.send(chunk[0]);
  await async {};
  s.expect(#ready 1, 0);

  result[1] := s.send(chunk[1]);
  await async {};
  s.expect(#ready 2, 0);

  chunk[0].release(#ok);
  await result[0];
  s.expect(#ready 2, 1);

  chunk[1].release(#ok);
  await result[1];
  s.expect(#ready 2, 2);

  s.assert_();
};

do {
  let s = Sender();
  let chunk = Array.tabulate<Chunk>(2, func(i) = Chunk());
  var result = Array.init<async ()>(chunk.size(), async ());

  result[0] := s.send(chunk[0]);
  await async {};
  s.expect(#ready 1, 0);

  result[1] := s.send(chunk[1]);
  await async {};
  s.expect(#ready 2, 0);

  chunk[0].release(#stop);
  await result[0];
  s.expect(#stopped, 0);

  chunk[1].release(#ok);
  await result[1];
  s.expect(#shutdown, 2);

  s.assert_();
};

do {
  let s = Sender();
  let chunk = Array.tabulate<Chunk>(2, func(i) = Chunk());
  var result = Array.init<async ()>(chunk.size(), async ());

  result[0] := s.send(chunk[0]);
  await async {};
  s.expect(#ready 1, 0);

  result[1] := s.send(chunk[1]);
  await async {};
  s.expect(#ready 2, 0);

  chunk[0].release(#gap);
  await result[0];
  s.expect(#paused, 0);

  chunk[1].release(#gap);
  await result[1];
  s.expect(#ready 0, 0);

  s.assert_();
};

do {
  let s = Sender();
  let chunk = Array.tabulate<Chunk>(2, func(i) = Chunk());
  var result = Array.init<async ()>(chunk.size(), async ());

  result[0] := s.send(chunk[0]);
  await async {};
  s.expect(#ready 1, 0);

  result[1] := s.send(chunk[1]);
  await async {};
  s.expect(#ready 2, 0);

  chunk[0].release(#reject);
  await result[0];
  s.expect(#paused, 0);

  chunk[1].release(#gap);
  await result[1];
  s.expect(#ready 0, 0);

  s.assert_();
};

do {
  let s = Sender();
  let N = StreamSender.MAX_CONCURRENT_CHUNKS_DEFAULT;
  let chunk = Array.tabulate<Chunk>(N, func(i) = Chunk());
  var result = Array.init<async ()>(chunk.size(), async ());

  for (i in Iter.range(0, N - 2)) {
    result[i] := s.send(chunk[i]);
    await async {};
    s.expect(#ready(i + 1), 0);
  };
  
  result[N - 1] := s.send(chunk[N - 1]);
  await async {};
  s.expect(#busy, 0);

  for (i in Iter.range(0, N - 1)) {
    chunk[i].release(#ok);
    await result[i];
  };

  s.assert_();
};
