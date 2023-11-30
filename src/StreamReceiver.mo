import Debug "mo:base/Debug";
import Error "mo:base/Error";
import R "mo:base/Result";
import Array "mo:base/Array";
import SWB "mo:swb";
import Types "Types";

module {

  /// Usage:
  ///
  /// let receiver = StreamReceiver<Int>(
  ///   123
  ///   func (streamId : Nat, element: Int, index: Nat): () {
  ///     ... do your logic with incoming item
  ///   }
  /// );
  ///
  /// Hook-up receive function in the actor class:
  /// public shared func onStreamChunk(streamId : Nat, chunk: [Int], firstIndex: Nat) : async () {
  ///   switch (streamId) case (123) { await receiver.onChunk(chunk, firstIndex); }; case (_) { Error.reject("Unknown stream"); }; };
  /// };
  ///
  /// The function `onChunk` throws in case of a gap (= broken pipe). The
  /// calling code should not catch the throw so that it gets passed through to
  /// the enclosing async expression of the calling code.
  public type Timeout = (Nat, () -> Int);
  public class StreamReceiver<T>(
    startPos : Nat,
    timeout : ?Timeout,
    itemCallback : (pos : Nat, item : T) -> (),
    // itemCallback is custom made per-stream and contains the streamId
  ) {

    var length_ : Nat = startPos;

    public func length() : Nat = length_;

    var lastChunkReceived_ : Int = switch (timeout) {
      case (?to) to.1 ();
      case (_) 0;
    };

    /// returns timestamp when stream received last chunk
    public func lastChunkReceived() : Int = lastChunkReceived_;

    /// returns flag if receiver timed out because of non-activity
    public func hasTimedOut() : Bool = switch (timeout) {
      case (?to)(to.1 () - lastChunkReceived_) > to.0;
      case (null) false;
    };

    /// processes a chunk and responds to sender
    public func onChunk(cm : Types.ChunkMsg<T>) : Types.ControlMsg {
      let (start, msg) = cm;
      if (start != length_) return #gap;
      if (hasTimedOut()) return #stopped;
      switch (msg) {
        case (#chunk ch) {
          for (i in ch.keys()) {
            itemCallback(start + i, ch[i]);
          };
          length_ += ch.size();
        };
        case (#ping) {};
      };
      switch (timeout) {
        case (?to) lastChunkReceived_ := to.1 ();
        case (_) {};
      };
      return #ok;
    };
  };
};
