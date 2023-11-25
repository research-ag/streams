import StreamReceiver "../src/StreamReceiver";
import StreamSender "../src/StreamSender";
import Buffer "mo:base/Buffer";

type Receiver = actor { receive : ([?Text], Nat) -> async Bool }; 

actor class A(r : Receiver) {
  let index = 0;
  public func send(t : Text) : async Bool { 
    await r.receive([?t], index);
  };
};

actor class B() {
  let received = Buffer.Buffer<?Text>(0);

  let receiver = StreamReceiver.StreamReceiver<?Text>(
    0,
    null,
    func(item : ?Text, index : Nat) {
      assert index == received.size();
      received.add(item);
    },
  );

  public func receive(items : [?Text], index : Nat) : async Bool { 
    await* receiver.onChunk(items, index);
  };

  public query func listReceived() : async [?Text] {
    Buffer.toArray(received);
  } 
};

let b = await B();
let a = await A(b);
assert ((await a.send("abc")) == true);
let list = await b.listReceived();
assert (list.size() == 1);
assert (list[0] == ?"abc");
