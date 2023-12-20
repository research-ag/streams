import StreamReceiver "../src/StreamReceiver";
import StreamSender "../src/StreamSender";
import { StreamReceiver = Receiver } "../src/StreamReceiver";
import { StreamSender = Sender } "../src/StreamSender";
import Buffer "mo:base/Buffer";
import Error "mo:base/Error";
import Time "mo:base/Time";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Iter "mo:base/Iter";
import Array "mo:base/Array";
import Types "../src/types";
import Base "sender.base";

type ChunkMessage = Types.ChunkMessage<?Text>;
type ControlMessage = Types.ControlMessage;
type Sender<T, S> = StreamSender.StreamSender<T, S>;
type Receiver<S> = StreamReceiver.StreamReceiver<S>;

func createReceiver() : Receiver<?Text> {
  let received = Buffer.Buffer<?Text>(0);

  let receiver = Receiver<?Text>(
    0,
    null,
    func(pos : Nat, item : ?Text) {
      assert pos == received.size();
      received.add(item);
    },
  );
  receiver;
};

func createSender(receiver : Receiver<?Text>) : Sender<Text, ?Text> {
  func send(ch : ChunkMessage) : async* ControlMessage { receiver.onChunk(ch) };

  let sender = Sender<Text, ?Text>(
    Base.create(1),
    send,
    null,
  );
  sender;
};

let receiver = createReceiver();
let sender = createSender(receiver);

func send() : async() {
  await* sender.sendChunk();
};

let n = 2;
for (i in Iter.range(0, n)) {
  ignore sender.push("a");
};

let result = Array.init<async ()>(n, async ());

result[0] := send();
await async {};

receiver.stop();

result[1] := send();
await async {};

assert sender.status() == #stopped;
Debug.print(debug_show sender.status());

assert (await sender.restart());
assert not receiver.isStopped();
await async {};

await send();
assert receiver.length() == n;

