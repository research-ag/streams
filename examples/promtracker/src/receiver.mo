import Int "mo:base/Int";
import Text "mo:base/Text";
import Time "mo:base/Time";
import PT "mo:promtracker";
import Stream "../../../src/StreamReceiver";
import HTTP "http";
import Tracker "tracker";

actor class Receiver() = self {
  type ControlMessage = Stream.ControlMessage;
  type ChunkMessage = Stream.ChunkMessage<?Text>;

  let receiver = Stream.StreamReceiver<?Text>(
    func(_ : Nat, _ : ?Text) {},
    ?(10 ** 15, Time.now),
  );

  let metrics = PT.PromTracker("", 65);

  let tracker = Tracker.Receiver(metrics);
  tracker.init(receiver);

  public shared func receive(message : ChunkMessage) : async ControlMessage {
    let ret = receiver.onChunk(message);
    tracker.onChunk(message, ret);
    ret;
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
