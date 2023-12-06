import StreamReceiver "../src/StreamReceiver";
import StreamSender "../src/StreamSender";
import { StreamReceiver = Receiver } "../src/StreamReceiver";
import { StreamSender = Sender } "../src/StreamSender";
import Buffer "mo:base/Buffer";
import Error "mo:base/Error";
import Time "mo:base/Time";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Types "../src/types";

type ChunkMsg = Types.ChunkMsg<?Text>;
type ControlMsg = Types.ControlMsg;
type Sender<T,S> = StreamSender.StreamSender<T,S>;
type Receiver<S> = StreamReceiver.StreamReceiver<S>;

func createReceiver() : Receiver<?Text> {
  let received = Buffer.Buffer<?Text>(0);

  let receiver = Receiver<?Text>(
    0,
    ?(10 ** 9, Time.now),
    func(pos : Nat, item : ?Text) {
      assert pos == received.size();
      received.add(item);
    },
  );
  receiver;
};

func createSender(receiver : Receiver<?Text>) : Sender<Text, ?Text> {
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

  func send(ch : ChunkMsg) : async* ControlMsg { receiver.onChunk(ch) };

  let sender = Sender<Text, ?Text>(
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

let n = sender.length();

var i = 0;
let max = 100;
while (sender.received() < n and i < max) {
  ignore await* sender.sendChunk();
  i += 1;
}; 
Debug.print("sent " # Nat.toText(i) # " chunks");
assert i != max;
