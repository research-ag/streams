import Stream "../../../src/StreamSender";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Text "mo:base/Text";
import PT "mo:promtracker";
import HTTP "http";

actor class Sender(receiverId : Principal) = self {
  let metrics = PT.PromTracker("", 65);
  metrics.addSystemValues();

  let chunkSizes = metrics.addGauge("chunk_sizes", "", #both, Array.tabulate<Nat>(5, func(i) = 2 ** i), false);
  let messageSizes = metrics.addGauge("message_sizes", "", #both, Array.tabulate<Nat>(5, func(i) = 2 ** i), false);
  let busyLevel = metrics.addGauge("busy_level", "", #both, Array.tabulate<Nat>(5, func(i) = 2 ** i), false);

  type ControlMessage = Stream.ControlMessage;
  type ChunkMessage = Stream.ChunkMessage<?Text>;

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

  func send(message : ChunkMessage) : async* ControlMessage {
    let size = switch (message.1) {
      case (#chunk a) a.size();
      case (_) 0;
    };
    chunkSizes.update(size);
    await receiver.receive(message);
  };

  let sender = Stream.StreamSender<Text, ?Text>(
    send,
    counter,
    null,
  );
  let sent = metrics.addPullValue("sent", "", func() = sender.sent());
  let received = metrics.addPullValue("sent", "", func() = sender.received());
  let length = metrics.addPullValue("sent", "", func() = sender.length());

  public shared func add(text : Text) : async () {
    messageSizes.update(text.size());
    Result.assertOk(sender.push(text));
  };

  system func heartbeat() : async () {
    busyLevel.update(sender.busyLevel());
    await* sender.sendChunk();
  };

  // metrics endpoint
  public query func http_request(req : HTTP.HttpRequest) : async HTTP.HttpResponse {
    let ?path = Text.split(req.url, #char '?').next() else return HTTP.render400();
    let labels = "canister=\"" # PT.shortName(self) # "\"";
    switch (req.method, path) {
      case ("GET", "/metrics") HTTP.renderPlainText(metrics.renderExposition(labels));
      case (_) HTTP.render400();
    };
  };
};
