import Array "mo:base/Array";
import Error "mo:base/Error";
import Int "mo:base/Int";
import Option "mo:base/Option";
import PT "mo:promtracker";
import Chunk "chunk";
import StremReceiver "../../../src/StreamReceiver";
import StreamSender "../../../src/StreamSender";
import Types "../../../src/types";

module {
  public class Receiver(
    metrics : PT.PromTracker
  ) {
    let chunk = Chunk.Chunk(metrics);

    public func init<T>(receiver : StremReceiver.StreamReceiver<T>) {
      chunk.init(receiver.lastChunkReceived);
      ignore metrics.addPullValue("internal_length", "", receiver.length);
    };

    public let onChunk = chunk.onChunk;
  };

  type SenderInterface = {
    busyLevel : () -> Nat;
    isPaused : () -> Bool;
    isStopped : () -> Bool;
    isShutdown : () -> Bool;
    queueSize : () -> Nat;
    sent : () -> Nat;
    received : () -> Nat;
    length : () -> Nat;
    lastChunkSent : () -> Int;
    var callbacks : StreamSender.Callbacks;
  };

  public class Sender(metrics : PT.PromTracker) {
    public let metrics = PT.PromTracker("", 65);
    var sender_ : ?SenderInterface = null;

    // on send 
    let busyLevel = metrics.addGauge("busy_level", "", #both, [], true);
    let queueSizePreBatch = metrics.addGauge("queue_size_pre_batch", "", #both, [], true);
    let queueSizePostBatch = metrics.addGauge("queue_size_post_batch", "", #both, [], true);
    let chunkSize = metrics.addGauge("chunk_size", "", #both, Array.tabulate<Nat>(8, func(i) = 8 ** i), false);
    let pings = metrics.addCounter("total_pings", "", true);
    let skips = metrics.addCounter("total_skips", "", true);

    // on response
    let oks = metrics.addCounter("total_oks", "", true);
    let gaps = metrics.addCounter("total_gaps", "", true);
    let stops = metrics.addCounter("total_stops", "", true);
    let errors = metrics.addCounter("total_errors", "", true);
    let stopFlag = metrics.addGauge("stop_flag", "", #both, [], true);
    let pausedFlag = metrics.addGauge("paused_flag", "", #both, [], true);
    let lastStopPos = metrics.addCounter("last_stop_pos", "", true);
    let lastRestartPos = metrics.addCounter("last_restart_pos", "", true);

    // on error
    let chunkErrorType = metrics.addGauge("chunk_error_type", "", #none, [0, 1, 2, 3, 4, 5, 6], true);

    public func init(sender : SenderInterface) {
      sender_ := ?sender;
      sender.callbacks := {
        onSend = onSend;
        onNoSend = onNoSend;
        onError = onError;
        onResponse = onResponse;
        onRestart = onRestart;
      };

      ignore metrics.addPullValue("sent", "", sender.sent);
      ignore metrics.addPullValue("received", "", sender.received);
      ignore metrics.addPullValue("length", "", sender.length);
      ignore metrics.addPullValue("last_chunk_sent", "", func() : Nat { Int.abs(sender.lastChunkSent()) / 10 ** 9 });
      ignore metrics.addPullValue("shutdown", "", func() = if (sender.isShutdown()) 1 else 0);
    };

    public func onSend(c : { #ping; #chunk : [Any] }) {
      let ?s = sender_ else return;
      busyLevel.update(s.busyLevel());
      queueSizePostBatch.update(s.queueSize());
      switch (c) {
        case (#ping) {
          pings.add(1);
          queueSizePreBatch.update(s.queueSize());
        };
        case (#chunk x) {
          chunkSize.update(x.size());
          queueSizePreBatch.update(s.queueSize() + x.size());
        }
      };
    };

    public func onNoSend() { skips.add(1) };
    public func onError(e : Error.Error) {
      let rejectCode = switch (Error.code(e)) {
        case (#call_error _) 0;
        case (#system_fatal) 1;
        case (#system_transient) 2;
        case (#destination_invalid) 3;
        case (#canister_reject) 4;
        case (#canister_error) 5;
        case (#future _) 7;
      };
      chunkErrorType.update(rejectCode);
    };
    public func onResponse(res : { #ok; #gap; #stop; #error }) {
      switch (res) {
        case (#ok) oks.add(1);
        case (#gap) gaps.add(1);
        case (#stop) stops.add(1);
        case (#error) errors.add(1);
      };
      let ?s = sender_ else return;
      stopFlag.update(if (s.isStopped()) 1 else 0);
      pausedFlag.update(if (s.isPaused()) 1 else 0);
      if (s.isStopped()) {
        lastStopPos.set(s.sent());
      };
    };
    public func onRestart() {
      let ?s = sender_ else return;
      lastRestartPos.set(s.sent());
    };

  };
};
