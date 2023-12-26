import SWB "mo:swb";
import Types "types";

module {
  /// Return type of processing function.
  public type ControlMessage = Types.ControlMessage;

  /// Argument of processing function.
  public type ChunkMessage<T> = Types.ChunkMessage<T>;

  /// Stable type of the receiver's memory.
  /// This can be declared with `stable let` and passed to the StreamReceiver constructor.
  public type ReceiverMem = {
    var length : Nat;
    var lastChunkReceived : Int;
    var stopped : Bool;
  };

  /// Creates a new, initialised receiver's memory.
  public func new() : ReceiverMem = {
    var length = 0;
    var lastChunkReceived = 0;
    var stopped = false;
  };

  /// StreamReceiver
  /// * receives chunk by `onChunk` call
  /// * validates `start` position in ChunkMessage (must match internal `length` variable)
  /// * calls `itemCallback` for each item of the chunk.
  ///
  /// Constructor arguments:
  /// * `startPos` is starting length
  /// * `timeout` is maximum waiting time between onChunk calls (default = infinite)
  /// * `itemCallback` function
  public class StreamReceiver<T>(
    mem : ReceiverMem,
    timeoutArg : ?(Nat, () -> Int),
    itemCallback : (pos : Nat, item : T) -> (),
  ) {
    func checkTime() {
      let ?arg = timeoutArg else return;
      let now = arg.1 ();
      if ((now - mem.lastChunkReceived) <= arg.0) {
        mem.lastChunkReceived := now;
      } else stop();
    };

    func resetTimeout() {
      let ?arg = timeoutArg else return;
      mem.lastChunkReceived := arg.1 ();
    };

    /// Returns `#gap` if start position in ChunkMessage does not match internal length.
    /// Returns `#stopped` if the receiver is already stopped or maximum waiting time between chunks is exceeded.
    /// Otherwise processes a chunk and call `itemCallback` on each item.
    /// A #ping message is handled equivalently to a #chunk of length zero.
    public func onChunk(cm : Types.ChunkMessage<T>) : Types.ControlMessage {
      let (start, msg) = cm;
      if (start != mem.length) return #gap;
      switch (msg) {
        case (#ping or #chunk _) {
          checkTime();
          if (mem.stopped) return #stop;
        };
        case (#restart) {
          resetTimeout();
          mem.stopped := false;
        };
      };
      let #chunk ch = msg else return #ok;
      for (i in ch.keys()) itemCallback(start + i, ch[i]);
      mem.length += ch.size();
      return #ok;
    };

    /// Manually stop the receiver.
    public func stop() = mem.stopped := true;

    /// Current number of received items.
    public func length() : Nat = mem.length;

    /// Timestamp when stream received last chunk
    public func lastChunkReceived() : Int = mem.lastChunkReceived;

    /// Flag if receiver is stopped (manually or by inactivity timeout)
    public func isStopped() : Bool = mem.stopped;
  };
};
