import Array "mo:base/Array";
import Int "mo:base/Int";
import Option "mo:base/Option";
import PT "mo:promtracker";
import Chunk "chunk";

module {
  public class Receiver(
    pull : {
      lastChunkReceived : () -> Int;
      length : () -> Nat;
    }
  ) {
    public let metrics = PT.PromTracker("", 65);
    let chunk = Chunk.Chunk(metrics, pull.lastChunkReceived);

    ignore metrics.addPullValue("internal_length", "", pull.length);

    public let onChunk = chunk.onChunk;
  };

  public class Sender(
    pull : {
      lastChunkReceived : () -> Int;
      sent : () -> Nat;
      received : () -> Nat;
      length : () -> Nat;
      busyLevel : () -> Nat;
    }
  ) {
    public let metrics = PT.PromTracker("", 65);
    let chunk = Chunk.Chunk(metrics, pull.lastChunkReceived);

    ignore metrics.addPullValue("sent", "", pull.sent);
    ignore metrics.addPullValue("received", "", pull.received);
    ignore metrics.addPullValue("length", "", pull.length);
    ignore metrics.addPullValue("busyLevel", "", pull.busyLevel);

    public let onChunk = chunk.onChunk;
  };
};
