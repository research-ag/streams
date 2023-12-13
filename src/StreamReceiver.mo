import Debug "mo:base/Debug";
import Error "mo:base/Error";
import R "mo:base/Result";
import Array "mo:base/Array";
import Time "mo:base/Time";
import SWB "mo:swb";
import Types "types";

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
  public type ControlMessage = Types.ControlMessage;
  public type ChunkMessage<T> = Types.ChunkMessage<T>;
  public type StableData = (Nat, Int);

  public class StreamReceiver<T>(
    startPos : Nat,
    timeout : ?Nat,
    itemCallback : (pos : Nat, item : T) -> (),
    // itemCallback is custom made per-stream and contains the streamId
  ) {
    var stopped_ = false;
    var length_ : Nat = startPos;

    var lastChunkReceived_ : Int = switch (timeout) {
      case (?to) Time.now();
      case (_) 0;
    };

    public func share() : StableData = (length_, lastChunkReceived_);

    public func unshare(data : StableData) {
      length_ := data.0;
      lastChunkReceived_ := data.1;
    };

    /// processes a chunk and responds to sender
    public func onChunk(cm : Types.ChunkMessage<T>) : Types.ControlMessage {
      let (start, msg) = cm;
      if (start != length_) return #gap;
      if (stopped()) return #stop;
      switch (msg) {
        case (#chunk ch) {
          for (i in ch.keys()) {
            itemCallback(start + i, ch[i]);
            length_ += 1;
          };
        };
        case (#ping) {};
      };
      switch (timeout) {
        case (?to) lastChunkReceived_ := Time.now();
        case (_) {};
      };
      return #ok;
    };

    public func stop() {
      stopped_ := true;
    };

    public func length() : Nat = length_;

    /// returns timestamp when stream received last chunk
    public func lastChunkReceived() : Int = lastChunkReceived_;

    /// returns flag if receiver timed out because of non-activity
    public func stopped() : Bool {
      stopped_ or (
        switch (timeout) {
          case (?to)(Time.now() - lastChunkReceived_) > to;
          case (null) false;
        }
      );
    };
  };
};
