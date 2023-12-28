import Array "mo:base/Array";
import Int "mo:base/Int";
import Option "mo:base/Option";
import PT "mo:promtracker";
import Types "../../../src/types";

module {
  public type ChunkMessage = (Nat, { #chunk : [Any]; #ping; #restart });

  public class Chunk(metrics : PT.PromTrackerTestable) {
    var time_ = func() : Int = (0 : Int);
    func time() : Nat = Int.abs(time_());

    var previousTime : Nat = 0;

    // gauges
    let chunkSize = metrics.addGauge("chunk_size", "", #both, Array.tabulate<Nat>(8, func(i) = 8 ** i), false);
    let stopFlag = metrics.addGauge("stop_flag", "", #both, [], false);

    // pulls
    ignore metrics.addPullValue("internal_last_chunk_received", "", time);

    // counters
    let chunksOk = metrics.addCounter("total_chunks_ok", "", true);
    let pingsOk = metrics.addCounter("total_pings_ok", "", true);
    let gaps = metrics.addCounter("total_gaps", "", true);
    let stops = metrics.addCounter("total_stops", "", true);
    let errors = metrics.addCounter("total_errors", "", true);
    let restarts = metrics.addCounter("total_restarts", "", true);
    let lastStopPos = metrics.addCounter("last_stop_pos", "", true);
    let lastErrorStopPos = metrics.addCounter("last_error_stop_pos", "", true);
    let lastRestartPos = metrics.addCounter("last_restart_pos", "", true);

    let timeSinceLastChunk = metrics.addGauge("time_since_last_chunk", "", #both, [], false);

    public func init(time : () -> Int) {
      time_ := time;
    };

    public func onChunk(msg : Types.ChunkMessage<Any>, ret : Types.ControlMessage or { #error; }) {
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
        case (_, #error) {
          lastErrorStopPos.set(pos);
          errors.add(1);
        }
      };
      let t = time();
      if (ret != #gap and msg.1 != #restart and previousTime != 0) {
        timeSinceLastChunk.update(t - previousTime);
      };
      previousTime := t;
    };
  };
};
