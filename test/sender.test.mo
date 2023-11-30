import StreamSender "../src/StreamSender";
import Types "../src/Types";
import Result "mo:base/Result";

let MAX_LENGTH = 5;

class counter() {
  var sum = 0;
  // Any individual item larger than MAX_LENGTH is wrapped to null
  // and its size is not counted.
  func wrap(item : Text) : (?Text, Nat) {
    let s = item.size();
    if (s <= MAX_LENGTH) (?item, s) else (null, 0);
  };
  public func accept(item : Text) : ??Text {
    let (wrapped, size) = wrap(item);
    sum += size;
    if (sum <= MAX_LENGTH) ?wrapped else null;
  };
};

func send(message : Types.ChunkMsg<?Text>) : async* Types.ControlMsg {
  assert message == (0, #chunk([?"abc"]));
  #ok;
};

let sender = StreamSender.StreamSender<Text, ?Text>(
  counter,
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
assert (await* sender.sendChunk()) == #ok;
