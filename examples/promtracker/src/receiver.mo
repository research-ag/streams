import Stream "../../../src/StreamReceiver";
import Buffer "mo:base/Buffer";
import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Text "mo:base/Text";
import PT "mo:promtracker";
import HTTP "http";

actor class Receiver() = self {
  let metrics = PT.PromTracker("", 65);
  metrics.addSystemValues();

  let chunkSizes = metrics.addGauge("chunk_sizes", "", #both, Array.tabulate<Nat>(5, func(i) = 2 ** i), false);
  let messageSizes = metrics.addGauge("message_sizes", "", #both, Array.tabulate<Nat>(5, func(i) = 2 ** i), false);

  type ControlMessage = Stream.ControlMessage;
  type ChunkMessage = Stream.ChunkMessage<?Text>;

  let received = Buffer.Buffer<?Text>(0);

  let receiver = Stream.StreamReceiver<?Text>(
    func(index : Nat, item : ?Text) {
      assert received.size() == index;
      received.add(item);
    },
    null,
  );

  let length = metrics.addPullValue("sent", "", func() = receiver.length());

  public shared func receive(message : ChunkMessage) : async ControlMessage {
    let size = switch (message.1) {
      case (#chunk a) a.size();
      case (_) 0;
    };
    chunkSizes.update(size);
    receiver.onChunk(message);
  };

  public query func lastReceived() : async ??Text {
    if (received.size() == 0) { null } else {
      ?received.get(received.size() - 1);
    };
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
