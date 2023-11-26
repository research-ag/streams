import Debug "mo:base/Debug";
import Error "mo:base/Error";
import R "mo:base/Result";
import Array "mo:base/Array";
import SWB "mo:swb";

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
  public type Chunk<T> = (Nat, [T]);
  public type ControlMsg = { #stop; #ok }; 
  public type Timeout = ( Nat, () -> Int );
  public class StreamReceiver<T>(
    startIndex : Nat,
    timeout : ?Timeout,
    itemCallback : (item : T, index : Nat) -> (),
    // itemCallback is custom made per-stream and contains the streamId
  ) {

    var length_ : Nat = startIndex;

    public func length() : Nat = length_;

    var lastChunkReceived_ : Int = switch (timeout) {
      case (?to) to.1();
      case (_) 0;
    };

    /// returns timestamp when stream received last chunk
    public func lastChunkReceived() : Int = lastChunkReceived_;

    /// returns flag if receiver timed out because of non-activity
    public func hasTimedOut() : Bool = switch (timeout) {
      case (?to)(to.1() - lastChunkReceived_) > to.0;
      case (null) false;
    };

    /// a function, should be called by shared function or stream manager
    // This function is async* so that can throw an Error.
    // It does not make any subsequent calls.
    public func onChunk(ch : Chunk<T>) : async* ControlMsg {
      let (firstIndex, chunk) = ch;
      if (firstIndex != length_) {
        throw Error.reject("Broken pipe in StreamReceiver");
      };
      if (hasTimedOut()) return #stop;
      switch (timeout) {
        case (?to) lastChunkReceived_ := to.1();
        case (_) {};
      };
      for (i in chunk.keys()) {
        itemCallback(chunk[i], firstIndex + i);
      };
      length_ := firstIndex + chunk.size();
      return #ok;
    };
  };
};
