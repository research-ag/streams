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

// Note: A chunk response of #trap (aka canister_error) cannot be simulated with
// the moc interpreter. Calling Debug.trap() to generate the error would
// instantly terminate the whole test.
type ChunkResponse = { #ok; #gap; #stopped; #reject; #none };

class Chunk(type_ : ChunkResponse) = {
  public var lock = true;
  public func run() : async Types.ControlMsg {
    while (lock) await async {};
    switch (type_) {
      case (#ok) #ok;
      case (#gap) #gap;
      case (#stopped) #stopped;
      case (#reject) throw Error.reject("");
      case (#none) Debug.trap("chunk was not expected to be sent");
    };
  };
  public func release() = lock := false;
};

var chunkRegister : Chunk = Chunk(#ok);
func load(c : Chunk) {
  chunkRegister := c;
};

func sendChunkMsg(message : Types.ChunkMsg<?Text>) : async* Types.ControlMsg {
  let c = chunkRegister;
  await c.run();
};

do {
  let sender = StreamSender.StreamSender<Text, ?Text>(
    create(5),
    sendChunkMsg,
    {
      maxQueueSize = null;
      maxConcurrentChunks = null;
      keepAliveSeconds = null;
    },
  );

  func send(c : Chunk, txt : Text) : async () {
    chunkRegister := c;
    Debug.print("send " # txt # ": " # debug_show sender.status());
    try {
      await* sender.sendChunk();
      Debug.print("return " # txt # ": " # debug_show sender.lastResponse() # " -> " # debug_show sender.status());
    } catch (e) {
      Debug.print("return " # txt # ": didn't send");
    };
  };

  func expect(st : StreamSender.Status, pos : Nat) : async () {
    Debug.print("expect " # debug_show st # " start= " # debug_show sender.received());
    assert sender.status() == st;
    assert sender.received() == pos;
  };

  for (i in Iter.range(1, 10)) {
    Result.assertOk(sender.push("abc"));
  };

  let t = [#ok, #reject, #gap, #none, #ok, #ok];
  let c = Array.map<ChunkResponse, Chunk>(t, func(x) = Chunk(x));
  var r = Array.init<async ()>(t.size(), async ());

  var i = 0;
  // Note: We cannot pass futures across contexts, neither as arguments to
  // functions nor return them from functions. We cannot read or write the
  // global r[] array from within a function either. That's why it is hard to
  // shorten the commands below with any kind of convenience function.

  r[0] := send(c[0], "0"); ignore expect(#ready 1, 0); // send chunk 0
  r[1] := send(c[1], "1"); ignore expect(#ready 2, 0); // send chunk 1
  r[2] := send(c[2], "2"); ignore expect(#ready 3, 0 ); // send chunk 2
  c[2].release(); await r[2]; ignore expect(#paused, 0); // return chunk 2
  c[0].release(); await r[0]; ignore expect(#paused, 1); // return chunk 0
  r[3] := send(c[3], "3"); await r[3]; ignore expect(#paused, 1); // send chunk 3, returns immediately 
  c[1].release(); await r[1]; ignore expect(#ready 1, 1); // return chunk 1
  r[4] := send(c[4], "4"); ignore expect(#ready 2, 1); // send chunk 4
  r[5] := send(c[5], "5"); ignore expect(#ready 3, 1); // send chunk 5
  c[4].release(); await r[4]; ignore expect(#ready 3, 2); // return chunk 4
  c[5].release(); await r[5]; ignore expect(#ready 3, 3); // return chunk 5
};
