import StreamSender "../src/StreamSender";
import Types "../src/Types";
import Result "mo:base/Result";
import Array "mo:base/Array";
import Char "mo:base/Char";
import Nat "mo:base/Nat";
import Iter "mo:base/Iter";
import Nat32 "mo:base/Nat32";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Base "sender.base";

do {
  let N = 26;
  let array = Array.tabulate<Text>(N, func(i) = "ab" # Char.toText(Char.fromNat32(Nat32.fromNat(i))));

  var i = 0;
  func send(message : Types.ChunkMsg<?Text>) : async* Types.ControlMsg {
    assert message == (i, #chunk([?array[i]]));
    #ok;
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(
    Base.create(5),
    send,
    {
      maxQueueSize = null;
      maxConcurrentChunks = null;
      keepAliveSeconds = null;
    },
  );

  for (i in Iter.range(0, N - 1)) {
    Result.assertOk(sender.push(array[i]));
  };

  while (i < N) {
    assert sender.status() == #ready i;
    await* sender.sendChunk();
    i += 1;
  };
};

do {
  let N = 26;
  let array = Array.tabulate<Text>(N, func(i) = "ab" # Char.toText(Char.fromNat32(Nat32.fromNat(i))));

  var i = 0;

  func send(message : Types.ChunkMsg<?Text>) : async* Types.ControlMsg {
    assert message == (2 * i, #chunk([?array[2 * i], ?array[2 * i + 1]]));
    #ok;
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(
    Base.create(6),
    send,
    {
      maxQueueSize = null;
      maxConcurrentChunks = null;
      keepAliveSeconds = null;
    },
  );

  for (i in Iter.range(0, N - 1)) {
    Result.assertOk(sender.push(array[i]));
  };

  while (i < N / 2) {
    assert sender.status() == #ready(2 * i);
    await* sender.sendChunk();
    i += 1;
  };
};

do {
  func send(message : Types.ChunkMsg<?Text>) : async* Types.ControlMsg {
    #stopped;
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(
    Base.create(5),
    send,
    {
      maxQueueSize = null;
      maxConcurrentChunks = null;
      keepAliveSeconds = null;
    },
  );
  Result.assertOk(sender.push("abc"));
  await* sender.sendChunk();
  assert sender.status() == #stopped;
};

do {
  func send(message : Types.ChunkMsg<?Text>) : async* Types.ControlMsg {
    #gap;
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(
    Base.create(5),
    send,
    {
      maxQueueSize = null;
      maxConcurrentChunks = null;
      keepAliveSeconds = null;
    },
  );
  Result.assertOk(sender.push("abc"));
  assert sender.status() == #ready 0;
  await* sender.sendChunk();
  assert sender.status() == #ready 0;
};

