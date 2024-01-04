import Array "mo:base/Array";
import Error "mo:base/Error";
import Int "mo:base/Int";
import Option "mo:base/Option";
import Time "mo:base/Time";
import PT "mo:promtracker";
import StreamReceiver "../../../src/StreamReceiver";
import StreamSender "../../../src/StreamSender";
import Types "../../../src/types";

module {

  type ReceiverInterface = {
    length : () -> Nat;
    var callbacks : StreamReceiver.Callbacks;
  };

  public class Receiver(metrics : PT.PromTracker, stable_ : Bool) {
    var receiver_ : ?ReceiverInterface = null;
    var previousTime : Nat = 0;

    // gauges
    let chunkSize = metrics.addGauge("chunk_size", "", #both, Array.tabulate<Nat>(8, func(i) = 8 ** i), stable_);
    let stopFlag = metrics.addGauge("stop_flag", "", #both, [], stable_);

    // pulls
    ignore metrics.addPullValue("last_chunk_received", "", func() = previousTime);

    // counters
    let chunksOk = metrics.addCounter("total_chunks_ok", "", stable_);
    let pingsOk = metrics.addCounter("total_pings_ok", "", stable_);
    let gaps = metrics.addCounter("total_gaps", "", stable_);
    let stops = metrics.addCounter("total_stops", "", stable_);
    let restarts = metrics.addCounter("total_restarts", "", stable_);
    let lastStopPos = metrics.addCounter("last_stop_pos", "", stable_);
    let lastRestartPos = metrics.addCounter("last_restart_pos", "", stable_);
    let timeSinceLastChunk = metrics.addGauge("time_since_last_chunk", "", #both, [], stable_);

    public func init(receiver : ReceiverInterface) {
      receiver_ := ?receiver;
      receiver.callbacks := {
        onChunk = onChunk;
      };
      ignore metrics.addPullValue("length", "", receiver.length);
    };

    public func onChunk(info : Types.ChunkMessageInfo, ret : Types.ControlMessage) {
      //let ?r = receiver_ else return;
      let (pos, msg) = info;
      switch (msg, ret) {
        case (#chunk size, #ok) {
          chunksOk.add(1);
          chunkSize.update(size);
        };
        case (#ping, #ok) pingsOk.add(1);
        case (#restart, #ok) {
          restarts.add(1);
          stopFlag.update(0);
          lastRestartPos.set(pos);
        };
        case (_, #gap) gaps.add(1);
        case (_, #stop) {
          stops.add(1);
          stopFlag.update(1);
          lastStopPos.set(pos);
        };
      };
      let now = Int.abs(Time.now()) / 10 ** 6;
      if (ret != #gap and msg != #restart and previousTime != 0) {
        timeSinceLastChunk.update(now - previousTime);
      };
      previousTime := now;
    };

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
    windowSize : () -> Nat;
    var callbacks : StreamSender.Callbacks;
  };

  public class Sender(metrics : PT.PromTracker, stable_ : Bool) {
    var sender_ : ?SenderInterface = null;

    // on send
    let busyLevel = metrics.addGauge("window_size", "", #both, [], stable_);
    let queueSizePreBatch = metrics.addGauge("queue_size_pre_batch", "", #both, [], stable_);
    let queueSizePostBatch = metrics.addGauge("queue_size_post_batch", "", #both, [], stable_);
    let chunkSize = metrics.addGauge("chunk_size", "", #both, Array.tabulate<Nat>(8, func(i) = 8 ** i), stable_);
    let pings = metrics.addCounter("total_pings", "", stable_);
    let skips = metrics.addCounter("total_skips", "", stable_);

    // on response
    let oks = metrics.addCounter("total_oks", "", stable_);
    let gaps = metrics.addCounter("total_gaps", "", stable_);
    let stops = metrics.addCounter("total_stops", "", stable_);
    let errors = metrics.addCounter("total_errors", "", stable_);
    let stopFlag = metrics.addGauge("stop_flag", "", #both, [], stable_);
    let pausedFlag = metrics.addGauge("paused_flag", "", #both, [], stable_);
    let lastStopPos = metrics.addCounter("last_stop_pos", "", stable_);
    let lastRestartPos = metrics.addCounter("last_restart_pos", "", stable_);

    // on error
    let chunkErrorType = metrics.addGauge("chunk_error_type", "", #none, [0, 1, 2, 3, 4, 5, 6], stable_);

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
      ignore metrics.addPullValue("setting_window_size", "", sender.windowSize);
    };

    public func onSend(c : Types.ChunkInfo) {
      let ?s = sender_ else return;
      busyLevel.update(s.busyLevel());
      queueSizePostBatch.update(s.queueSize());
      switch (c) {
        case (#ping) {
          pings.add(1);
          queueSizePreBatch.update(s.queueSize());
        };
        case (#chunk size) {
          chunkSize.update(size);
          queueSizePreBatch.update(s.queueSize() + size);
        };
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
