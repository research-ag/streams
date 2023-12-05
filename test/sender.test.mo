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

var trapped = false;
func trap() {
  // Note: The interpreter does not roll back state changes. Hence trapped := true
  // will take effect despite the assert false.
  trapped := true;
  assert false;
};
func myassert(b : Bool) {
  if (not b) {
    Debug.print("==== assertion failure. Stopping test here. ====");
    trap();
  };
};

// Note: A chunk response of #trap (aka canister_error) cannot be simulated with
// the moc interpreter. Calling Debug.trap() to generate the error would
// instantly terminate the whole test.

type ChunkResponse = { #ok; #gap; #stopped; #reject };

class Chunk(name_ : Text) = {
  var response : ?ChunkResponse = null;
  public func name() : Text = name_;
  public func run() : async Types.ControlMsg {
    while (response == null and not trapped) await async {};
    switch (response) {
      case (? #ok) #ok;
      case (? #gap) #gap;
      case (? #stopped) #stopped;
      case (? #reject) throw Error.reject("");
      case (null) #stopped;
    };
    // Note: In case null the test is aborted due to an assertion failure
    // elsewhere.  We make all chunk respond with #stopped as if the receiver
    // had stopped the stream. It does not really matter what we return here
    // though we expect that #stopped will lead to cleaner debug output than
    // other choices.
  };
  public func respond(r : ChunkResponse) = response := ?r;
};

var chunkRegister : Chunk = Chunk("initial");
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
    let txt = c.name() # ": ";
    Debug.print("send " # txt # debug_show sender.status());
    try {
      await* sender.sendChunk();
      Debug.print("return " # txt # debug_show sender.lastResponse() # " -> " # debug_show sender.status());
    } catch (e) {
      Debug.print("return " # txt # "didn't send");
    };
  };

  func expect(st : StreamSender.Status, pos : Nat) : () {
    Debug.print("expect " # debug_show st # " start= " # debug_show sender.received());
    myassert(sender.status() == st);
    myassert(sender.received() == pos);
  };

  for (i in Iter.range(1, 10)) {
    switch (sender.push("abc")) {
      case (#err _) myassert(false);
      case (_) {};
    };
  };

  let c = Array.tabulate<Chunk>(6, func(i) = Chunk(Nat.toText(i)));
  var r = Array.init<async ()>(c.size(), async ());

  var i = 0;
  // Note: We cannot pass futures across contexts, neither as arguments to
  // functions nor return them from functions. We cannot read or write the
  // global r[] array from within a function either. That's why it is hard to
  // shorten the commands below with any kind of convenience function.

  r[0] := send(c[0]); await async expect(#ready 1, 0); // send chunk 0
  r[1] := send(c[1]); await async expect(#ready 2, 0); // send chunk 1
  r[2] := send(c[2]); await async expect(#ready 3, 0 ); // send chunk 2
  c[2].respond(#gap); await r[2]; expect(#paused, 0); // return chunk 2
  c[0].respond(#ok); await r[0]; expect(#paused, 1); // return chunk 0
  r[3] := send(c[3]); await r[3]; expect(#paused, 1); // send chunk 3, but it does not send
  c[1].respond(#reject); await r[1]; expect(#ready 1, 1); // return chunk 1
  r[4] := send(c[4]); await async expect(#ready 2, 1); // send chunk 4
  r[5] := send(c[5]); await async expect(#ready 3, 1); // send chunk 5
  c[4].respond(#ok); await r[4]; expect(#ready 3, 2); // return chunk 4
  c[5].respond(#ok); await r[5]; expect(#ready 3, 3); // return chunk 5
};
