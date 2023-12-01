import StreamSender "../src/StreamSender";
import Types "../src/Types";
import Result "mo:base/Result";
import Array "mo:base/Array";
import Char "mo:base/Char";
import Nat "mo:base/Nat";
import Iter "mo:base/Iter";
import Nat32 "mo:base/Nat32";
import Debug "mo:base/Debug";

func create(maxLength : Nat) : (() -> { accept : (item : Text) -> ??Text }) {
  class counter() {
    var sum = 0;
    // Any individual item larger than maxLength is wrapped to null
    // and its size is not counted.
    func wrap(item : Text) : (?Text, Nat) {
      let s = item.size();
      if (s <= maxLength) (?item, s) else (null, 0);
    };
    public func accept(item : Text) : ??Text {
      let (wrapped, size) = wrap(item);
      sum += size;
      if (sum <= maxLength) ?wrapped else null;
    };
  };
  counter;
};

// do {
//   let N = 26;
//   let array = Array.tabulate<Text>(N, func(i) = "ab" # Char.toText(Char.fromNat32(Nat32.fromNat(i))));

//   var i = 0;
//   func send(message : Types.ChunkMsg<?Text>) : async* Types.ControlMsg {
//     assert message == (i, #chunk([?array[i]]));
//     #ok;
//   };

//   let sender = StreamSender.StreamSender<Text, ?Text>(
//     create(5),
//     send,
//     {
//       maxQueueSize = null;
//       maxConcurrentChunks = null;
//       keepAliveSeconds = null;
//     },
//   );

//   for (i in Iter.range(0, N - 1)) {
//     Result.assertOk(sender.push(array[i]));
//   };

//   while (i < N) {
//     assert sender.status() == #ready i;
//     await* sender.sendChunk();
//     i += 1;
//   };
// };

// do {
//   let N = 26;
//   let array = Array.tabulate<Text>(N, func(i) = "ab" # Char.toText(Char.fromNat32(Nat32.fromNat(i))));

//   var i = 0;

//   func send(message : Types.ChunkMsg<?Text>) : async* Types.ControlMsg {
//     assert message == (2 * i, #chunk([?array[2 * i], ?array[2 * i + 1]]));
//     #ok;
//   };

//   let sender = StreamSender.StreamSender<Text, ?Text>(
//     create(6),
//     send,
//     {
//       maxQueueSize = null;
//       maxConcurrentChunks = null;
//       keepAliveSeconds = null;
//     },
//   );

//   for (i in Iter.range(0, N - 1)) {
//     Result.assertOk(sender.push(array[i]));
//   };

//   while (i < N / 2) {
//     assert sender.status() == #ready(2 * i);
//     await* sender.sendChunk();
//     i += 1;
//   };
// };

// do {
//   func send(message : Types.ChunkMsg<?Text>) : async* Types.ControlMsg {
//     #stopped;
//   };

//   let sender = StreamSender.StreamSender<Text, ?Text>(
//     create(5),
//     send,
//     {
//       maxQueueSize = null;
//       maxConcurrentChunks = null;
//       keepAliveSeconds = null;
//     },
//   );
//   Result.assertOk(sender.push("abc"));
//   await* sender.sendChunk();
//   assert sender.status() == #stopped;
// };

// do {
//   func send(message : Types.ChunkMsg<?Text>) : async* Types.ControlMsg {
//     #gap;
//   };

//   let sender = StreamSender.StreamSender<Text, ?Text>(
//     create(5),
//     send,
//     {
//       maxQueueSize = null;
//       maxConcurrentChunks = null;
//       keepAliveSeconds = null;
//     },
//   );
//   Result.assertOk(sender.push("abc"));
//   assert sender.status() == #ready 0;
//   await* sender.sendChunk();
//   assert sender.status() == #ready 0;
// };

do {
  func send(message : Types.ChunkMsg<?Text>) : async* Types.ControlMsg {
    #gap;
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(
    create(5),
    send,
    {
      maxQueueSize = null;
      maxConcurrentChunks = null;
      keepAliveSeconds = null;
    },
  );
  Result.assertOk(sender.push("abc"));
  Result.assertOk(sender.push("abc"));
  Result.assertOk(sender.push("abc"));

  let a1 = async {
    sender.status();
  };

  ignore async {
    await* sender.sendChunk();
  };
  
  let a2 = async {
    sender.status();
  };

  ignore async {
    await* sender.sendChunk();
  };

  let a3 = async {
    sender.status();
  };
  
  await async {};

  Debug.print(debug_show (await a1));
  Debug.print(debug_show (await a2));
  Debug.print(debug_show (await a3));
};
