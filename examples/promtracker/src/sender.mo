import Stream "../../../src/StreamSender";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Text "mo:base/Text";
import Time "mo:base/Time";
import PT "mo:promtracker";
import HTTP "http";
import Tracker "tracker";

actor class Sender(receiverId : Principal) = self {
  type ControlMessage = Stream.ControlMessage;
  type ChunkMessage = Stream.ChunkMessage<?Text>;

  let metrics = PT.PromTracker("", 65);

  let receiver = actor (Principal.toText(receiverId)) : actor {
    receive : (message : ChunkMessage) -> async ControlMessage;
  };

  let MAX_LENGTH = 30;

  class counter() {
    var sum = 0;
    func wrap(item : Text) : (?Text, Nat) {
      let s = (to_candid (item)).size();
      if (s <= MAX_LENGTH) (?item, s) else (null, 0);
    };
    public func accept(item : Text) : ??Text {
      let (wrapped, size) = wrap(item);
      sum += size;
      if (sum <= MAX_LENGTH) ?wrapped else null;
    };
  };

  var tracker : ?Tracker.Sender = null;

  func send(message : ChunkMessage) : async* ControlMessage {
    let ret = await receiver.receive(message);
    let ?t = tracker else return ret;
    t.onChunk(message, ret);
    ret;
  };

  let sender = Stream.StreamSender<Text, ?Text>(
    send,
    counter,
    null,
  );

  sender.setKeepAlive(?(10 ** 15, Time.now));

  tracker := ?Tracker.Sender(metrics, sender);

  public shared func add(text : Text) : async () {
    Result.assertOk(sender.push(text));
  };

  system func heartbeat() : async () {
    await* sender.sendChunk();
  };

  // metrics endpoint
  public query func http_request(req : HTTP.HttpRequest) : async HTTP.HttpResponse {
    let ?path = Text.split(req.url, #char '?').next() else return HTTP.render400();
    let labels = "canister=\"" # PT.shortName(self) # "\"";
    switch (req.method, path, tracker) {
      case ("GET", "/metrics", ?t) HTTP.renderPlainText(metrics.renderExposition(labels));
      case (_) HTTP.render400();
    };
  };
};
