import Debug "mo:base/Debug";
import Error "mo:base/Error";
import R "mo:base/Result";
import Time "mo:base/Time";
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
  public class StreamReceiver<T>(
    startIndex : Nat,
    timeoutSeconds : ?Nat,
    itemCallback : (item : T, index : Nat) -> (),
    // itemCallback is custom made per-stream and contains the streamId
  ) {

    var expectedNextIndex_ : Nat = startIndex;
    // rename to length_?
    var lastChunkReceived_ : Time.Time = Time.now();

    public func length() : Nat = expectedNextIndex_;

    let timeout : ?Nat = switch (timeoutSeconds) {
      case (?s) ?(s * 1_000_000_000);
      case (null) null;
    };

    /// returns timestamp when stream received last chunk
    public func lastChunkReceived() : Time.Time = lastChunkReceived_;

    /// returns flag is receiver closed stream with timeout
    public func isClosed() : Bool = switch (timeout) {
      case (?to)(Time.now() - lastChunkReceived_) > to;
      case (null) false;
    };

    /// a function, should be called by shared function or stream manager
    // This function is async* so that can throw an Error.
    // It does not make any subsequent calls.
    public func onChunk(chunk : [T], firstIndex : Nat) : async* Bool {
      if (firstIndex != expectedNextIndex_) {
        throw Error.reject("Broken pipe in StreamReceiver");
      };
      if (isClosed()) return false;
      lastChunkReceived_ := Time.now();
      for (i in chunk.keys()) {
        itemCallback(chunk[i], firstIndex + i);
      };
      expectedNextIndex_ := firstIndex + chunk.size();
      return true;
    };

    // should be used only in internal streams
    public func insertItem(item : T) : Nat {
      itemCallback(item, expectedNextIndex_);
      expectedNextIndex_ += 1;
      expectedNextIndex_ - 1;
    };
  };
};
