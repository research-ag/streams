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
type ChunkResponse = { #ok; #gap; #stopped; #reject };

class Chunk(type_ : ChunkResponse) = {
  var lock = true;
  public func run() : async Types.ControlMsg {
    while (lock) await async {};
    switch (type_) {
      case (#ok) #ok;
      case (#gap) #gap;
      case (#stopped) #stopped;
      case (#reject) throw Error.reject("");
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

  func send(c : Chunk) : async () {
    chunkRegister := c;
    Debug.print("send: " # debug_show sender.status());
    await* sender.sendChunk();
    Debug.print("return: " # debug_show sender.lastResponse() # " -> " # debug_show sender.status());
  };

  for (i in Iter.range(1, 10)) {
    Result.assertOk(sender.push("abc"));
  };

  let t = [#ok, #reject, #gap, #ok, #reject, #ok];
  let c = Array.map<ChunkResponse, Chunk>(t, func(x) = Chunk(x));
  var r = Array.init<async ()>(t.size(), async ());

  var i = 0;
  // Note: We cannot pass futures across contexts, neither as arguments to
  // functions nor return them from functions. We cannot read or write the
  // global r[] array from within a function either. The closest solution to
  // defining a convenience function was to make copy-pastable lines like the
  // ones below.
  
  i := 0; do { r[i] := send(c[i]) }; // send chunk 0
  i := 1; do { r[i] := send(c[i]) }; // send chunk 1
  i := 2; do { r[i] := send(c[i]) }; // send chunk 2
  i := 2; do { c[i].release(); await r[i] }; // return chunk 2
  i := 0; do { c[i].release(); await r[i] }; // return chunk 0
  i := 1; do { c[i].release(); await r[i] }; // return chunk 1
  i := 3; do { r[i] := send(c[i]) }; // send chunk 3
  i := 3; do { c[i].release(); await r[i] }; // return chunk 3
};
