import StreamSender "../src/StreamSender";
import Types "../src/types";
import Result "mo:base/Result";
import Array "mo:base/Array";
import Char "mo:base/Char";
import Nat "mo:base/Nat";
import Iter "mo:base/Iter";
import Nat32 "mo:base/Nat32";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Base "sender.base";

// sequential successful sends, chunk length = 1
do {
  let N = 26;
  let array = Array.tabulate<Text>(N, func(i) = "ab" # Char.toText(Char.fromNat32(Nat32.fromNat(i))));

  var i = 0;
  func send(message : Types.ChunkMessage<?Text>) : async* Types.ControlMessage {
    assert message == (i, #chunk([?array[i]]));
    #ok;
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(
    Base.create(5),
    send,
    null
  );

  for (i in Iter.range(0, N - 1)) {
    Result.assertOk(sender.push(array[i]));
  };

  while (i < N) {
    assert sender.status() == #ready;
    assert sender.sent() == i;
    await* sender.sendChunk();
    i += 1;
  };
};

// sequential successful sends, chunk length = 2
do {
  let N = 26;
  let array = Array.tabulate<Text>(N, func(i) = "ab" # Char.toText(Char.fromNat32(Nat32.fromNat(i))));

  var i = 0;

  func send(message : Types.ChunkMessage<?Text>) : async* Types.ControlMessage {
    assert message == (2 * i, #chunk([?array[2 * i], ?array[2 * i + 1]]));
    #ok;
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(
    Base.create(6),
    send,
    null,
  );

  for (i in Iter.range(0, N - 1)) {
    Result.assertOk(sender.push(array[i]));
  };

  while (i < N / 2) {
    assert sender.status() == #ready;
    assert sender.sent() == 2 * i;
    await* sender.sendChunk();
    i += 1;
  };
};

// #stop response
do {
  func send(message : Types.ChunkMessage<?Text>) : async* Types.ControlMessage {
    #stop;
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(
    Base.create(5),
    send,
    null,
  );
  Result.assertOk(sender.push("abc"));
  await* sender.sendChunk();
  assert sender.status() == #stopped;
};

// #gap response
do {
  func send(message : Types.ChunkMessage<?Text>) : async* Types.ControlMessage {
    #gap;
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(
    Base.create(5),
    send,
    null,
  );
  Result.assertOk(sender.push("abc"));
  assert sender.status() == #ready;
  assert sender.sent() == 0;
  await* sender.sendChunk();
  assert sender.status() == #ready;
  assert sender.sent() == 0;
};