import Array "mo:base/Array";
import Int "mo:base/Int";
import Option "mo:base/Option";
import PT "mo:promtracker";
import Chunk "chunk";
import StremReceiver "../../../src/StreamReceiver";
import StreamSender "../../../src/StreamSender";

module {
  public class Receiver(
    metrics : PT.PromTrackerTestable
  ) {
    let chunk = Chunk.Chunk(metrics);

    public func init<T>(receiver : StremReceiver.StreamReceiver<T>) {
      chunk.init(receiver.lastChunkReceived);
      ignore metrics.addPullValue("internal_length", "", receiver.length);
    };

    public let onChunk = chunk.onChunk;
  };

  public class Sender(metrics : PT.PromTrackerTestable) {
    public let metrics = PT.PromTracker("", 65);
    let chunk = Chunk.Chunk(metrics);

    public func init<T, S>(sender : StreamSender.StreamSender<T, S>) {
      chunk.init(sender.lastChunkSent);

      ignore metrics.addPullValue("sent", "", sender.sent);
      ignore metrics.addPullValue("received", "", sender.received);
      ignore metrics.addPullValue("length", "", sender.length);
      ignore metrics.addPullValue("busyLevel", "", sender.busyLevel);
    };

    public let onChunk = chunk.onChunk;
  };
};
