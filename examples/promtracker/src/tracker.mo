import Array "mo:base/Array";
import Int "mo:base/Int";
import Option "mo:base/Option";
import PT "mo:promtracker";

module {

  public type ChunkMessage = (Nat, { #chunk : [Any]; #ping; #restart });
  public type PullInterface = {
    lastChunkReceived : () -> Int;
    length : () -> Nat;
  };

  public class Receiver(pull : PullInterface) {
    public let metrics = PT.PromTracker("", 65);

    func time() : Nat = Int.abs(pull.lastChunkReceived());

    var previousTime : Nat = 0;

    // gauges
    let chunkSize = metrics.addGauge("chunk_size", "", #both, Array.tabulate<Nat>(8, func(i) = 8 ** i), false);
    let stopFlag = metrics.addGauge("stop_flag", "", #both, [], false);
    let timeSinceLastChunk = metrics.addGauge("time_since_last_chunk", "", #both, [], false);

    // counters
    let chunksOk = metrics.addCounter("total_chunks_ok", "", true);
    let pingsOk = metrics.addCounter("total_pings_ok", "", true);
    let gaps = metrics.addCounter("total_gaps", "", true);
    let stops = metrics.addCounter("total_stops", "", true);
    let restarts = metrics.addCounter("total_restarts", "", true);
    let lastStopPos = metrics.addCounter("last_stop_pos", "", true);
    let lastRestartPos = metrics.addCounter("last_restart_pos", "", true);

    // pull values
    ignore metrics.addPullValue("internal_last_chunk_received", "", time);
    ignore metrics.addPullValue("internal_length", "", pull.length);

    public func onChunk(
      msg : ChunkMessage,
      ret : { #ok; #stop; #gap },
    ) {
      let pos = msg.0;
      switch (msg.1, ret) {
        case (#chunk c, #ok) {
          chunksOk.add(1);
          chunkSize.update(c.size());
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
      let t = time();
      if (ret != #gap and msg.1 != #restart and previousTime != 0) {
        timeSinceLastChunk.update(t - previousTime);
      };
      previousTime := t;
    };
  };

  public func shortName(a : actor {}) : Text = PT.shortName(a);

};
