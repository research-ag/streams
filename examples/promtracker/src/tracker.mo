import Array "mo:base/Array";
import Int "mo:base/Int";
import Option "mo:base/Option";
import PT "mo:promtracker";
import Chunk "chunk";
import StremReceiver "../../../src/StreamReceiver";
import StreamSender "../../../src/StreamSender";
import Types "../../../src/types";

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

    var busyLevelF = func() : Nat = 0;
    var pausedF = func() : Bool = false;
    var queueSizeF = func () : Nat = 0;

    let busyLevel = metrics.addGauge("busyLevel", "", #high, [], true);
    let paused = metrics.addGauge("paused", "", #both, [], true);
    let queueSize = metrics.addGauge("queueSize", "", #high, [], true);

    public func init<T, S>(sender : StreamSender.StreamSender<T, S>) {
      chunk.init(sender.lastChunkSent);
      busyLevelF := sender.busyLevel;
      pausedF := sender.isPaused;
      queueSizeF := sender.queueSize;

      ignore metrics.addPullValue("sent", "", sender.sent);
      ignore metrics.addPullValue("received", "", sender.received);
      ignore metrics.addPullValue("length", "", sender.length);
    };

    public func onChunk(msg : Types.ChunkMessage<Any>, ret : Types.ControlMessage or { #error; }) {
      busyLevel.update(busyLevelF());
      paused.update(if (pausedF()) 1 else 0);
      queueSize.update(queueSizeF());
      chunk.onChunk(msg, ret);
    };
  };
};
