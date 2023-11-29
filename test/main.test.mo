import StreamReceiver "../src/StreamReceiver";
import StreamSender "../src/StreamSender";
import Buffer "mo:base/Buffer";
import Error "mo:base/Error";
import Time "mo:base/Time";

func createReceiver() : StreamReceiver.StreamReceiver<?Text> {
  let received = Buffer.Buffer<?Text>(0);

  let receiver = StreamReceiver.StreamReceiver<?Text>(
    0,
    ?(10 ** 9, Time.now),
    func(pos : Nat, item : ?Text) {
      assert pos == received.size();
      received.add(item);
    },
  );
  receiver;
};

func createSender(receiver : StreamReceiver.StreamReceiver<?Text>) : StreamSender.StreamSender<Text, ?Text> {
  let MAX_LENGTH = 5;

  func counter() : { accept(Text) : ??Text } {
    var sum = 0;
    {
      accept = func(item : Text) : ??Text {
        let (wrapped_item, wrapped_size) = if (item.size() <= MAX_LENGTH) {
          (?item, item.size());
        } else {
          (null, 0);
        };
        sum += wrapped_size;
        if (sum <= MAX_LENGTH) ?wrapped_item else null;
      };
    };
  };

  func send(ch : StreamSender.ChunkMsg<?Text>) : async* StreamSender.ControlMsg {
    await* receiver.onChunk(ch);
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
