import StreamReceiver "../src/StreamReceiver";
import StreamSender "../src/StreamSender";
import Buffer "mo:base/Buffer";
import Error "mo:base/Error";
import Time "mo:base/Time";

func createReceiver() : StreamReceiver.StreamReceiver<?Text> {
  let received = Buffer.Buffer<?Text>(0);

  let receiver = StreamReceiver.StreamReceiver<?Text>(
    0,
    ?(10**9, Time.now),
    func(item : ?Text, index : Nat) {
      assert index == received.size();
      received.add(item);
    },
  );
  receiver;
};

func createSender(receiver : StreamReceiver.StreamReceiver<?Text>) : StreamSender.StreamSender<Text, ?Text> {
  let MAX_LENGTH = 5;

  func counter() : { accept(Text) : Bool } {
    var sum = 0;
    {
      accept = func(item : Text) : Bool {
        sum += item.size();
        sum <= MAX_LENGTH;
      };
    };
  };

  func wrap(item : Text) : ?Text {
    if (item.size() <= MAX_LENGTH) { ?item } else { null };
  };

  func send(ch : StreamSender.ChunkMsg<?Text>) : async* StreamSender.ControlMsg {
    await* receiver.onChunk(ch);
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(
    counter,
    wrap,
    send,
    {
      maxQueueSize = null;
      maxConcurrentChunks = null;
      keepAliveSeconds = null;
    },
  );
  sender;
};

let receiver = createReceiver();
let sender = createSender(receiver);

ignore sender.push("abc");
ignore sender.push("abcdef");
ignore sender.push("abc");
ignore sender.push("def");
ignore sender.push("get");
ignore sender.push("nmb");
ignore sender.push("abc");
ignore sender.push("abc");
ignore sender.push("abc");

await* sender.sendChunk();
await* sender.sendChunk();
await* sender.sendChunk();
await* sender.sendChunk();
/*
while (true) {
  await* sender.sendChunk();
};
*/
