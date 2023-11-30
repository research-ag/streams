import Debug "mo:base/Debug";
import Error "mo:base/Error";
import R "mo:base/Result";
import Time "mo:base/Time";
import Array "mo:base/Array";
import Option "mo:base/Option";
import SWB "mo:swb";
import Vector "mo:vector";
import Types "Types";

module {
  /// Usage:
  ///
  /// let sender = StreamSender<Int>(
  ///   123,
  ///   10,
  ///   10,
  ///   func (item) = 1,
  ///   5,
  ///   anotherCanister.appendStream,
  /// );
  /// sender.next(1);
  /// sender.next(2);
  /// .....
  /// sender.next(12);
  /// await* sender.sendChunk(); // will send (123, [1..10], 0) to `anotherCanister`
  /// await* sender.sendChunk(); // will send (123, [11..12], 10) to `anotherCanister`
  /// await* sender.sendChunk(); // will do nothing, stream clean
  public type SendChunkResult = Types.ControlMsg or {
    #callErrorTransient;
    #callErrorPermanent;
  };

  // T = queue item type
  // S = stream item type
  public class StreamSender<T, S>(
    counterCreator : () -> { accept(item : T) : ?S },
    sendFunc : (x : Types.ChunkMsg<S>) -> async* Types.ControlMsg,
    settings : {
      maxQueueSize : ?Nat;
      maxConcurrentChunks : ?Nat;
      keepAliveSeconds : ?Nat;
    },
  ) {
    let MAX_CONCURRENT_CHUNKS_DEFAULT = 5;

    let buffer = SWB.SlidingWindowBuffer<T>();

    let settings_ = {
      var maxQueueSize = settings.maxQueueSize;
      var maxConcurrentChunks = settings.maxConcurrentChunks;
      var keepAliveSeconds = settings.keepAliveSeconds;
    };

    var stopped = false;
    var head : ?Nat = ?0;
    var lastChunkSent = Time.now();
    var concurrentChunks = 0;

    func isQueueFull() : Bool = switch (settings_.maxQueueSize) {
      case (?max) buffer.len() >= max;
      case (null) false;
    };

    /// add item to the stream
    public func push(item : T) : {
      #ok : Nat;
      #err : { #NoSpace };
    } {
      if (isQueueFull())
      #err(#NoSpace) else
      #ok(buffer.add(item));
    };

    /// send chunk to the receiver
    public func sendChunk() : async* SendChunkResult {
      if (isStopped()) Debug.trap("Stream stopped");
      if (isBusy()) Debug.trap("Stream sender is busy");
      let ?start = head else Debug.trap("Stream sender is paused");

      let elements = do {
        var end = start;
        let counter = counterCreator();
        let vec = Vector.new<S>();
        label l loop {
          switch (buffer.getOpt(end)) {
            case (null) break l;
            case (?item) {
              switch (counter.accept(item)) {
                case (?x) Vector.add(vec, x);
                case (null) break l;
              };
              end += 1;
            };
          };
        };
        head := ?end;
        Vector.toArray(vec);
      };

      func shouldPing() : Bool {
        switch (settings_.keepAliveSeconds) {
          case (?i) lastChunkSent + i * 1_000_000_000 < Time.now();
          case (null) false;
        };
      };

      let chunkMsg = if (elements.size() == 0) {
        if (not shouldPing()) return #ok;
        (start, #ping);
      } else {
        (start, #chunk elements);
      };

      lastChunkSent := Time.now();
      concurrentChunks += 1;

      let end = start + elements.size();
      func receive() {
        concurrentChunks -= 1;
        if (concurrentChunks == 0 and head == null) {
          head := ?buffer.start();
        };
      };

      let res : SendChunkResult = try {
        await* sendFunc(chunkMsg);
      } catch (err) {
        switch (Error.code(err)) {
          case (#system_transient or #canister_error _ or #call_error _) #callErrorTransient;
          case (#system_fatal or #destination_invalid or #canister_reject or #future _) #callErrorPermanent;
        };
      };
      switch (res) {
        case (#ok) buffer.deleteTo(end);
        case (#stopped) {
          stopped := true;
          buffer.deleteTo(start);
        };
        case (#gap or #callErrorTransient _ or #callErrorPermanent _) head := null;
      };
      receive();
      res;
    };

    /// total amount of items, ever added to the stream sender, also an index, which will be assigned to the next item
    public func length() : Nat = buffer.end();

    /// amount of items, which were sent to receiver
    public func sent() : ?Nat = head;

    /// amount of items, successfully sent and acknowledged by receiver
    public func received() : Nat = buffer.start();

    /// get item from queue by index
    public func get(index : Nat) : ?T = buffer.getOpt(index);

    /// check busy status of sender
    public func isBusy() : Bool {
      concurrentChunks == Option.get(
        settings_.maxConcurrentChunks,
        MAX_CONCURRENT_CHUNKS_DEFAULT,
      );
    };

    /// check busy level of sender, e.g. current amount of outgoing calls in flight
    public func busyLevel() : Nat = concurrentChunks;

    /// returns flag is receiver stopped the stream
    public func isStopped() : Bool = stopped;

    /// check paused status of sender
    public func isPaused() : Bool = head == null;

    /// update max queue size
    public func setMaxQueueSize(value : ?Nat) {
      settings_.maxQueueSize := value;
    };

    /// update max amount of concurrent outgoing requests
    public func setMaxConcurrentChunks(value : ?Nat) {
      settings_.maxConcurrentChunks := value;
    };

    /// update max interval between stream calls
    public func setKeepAlive(seconds : ?Nat) {
      settings_.keepAliveSeconds := seconds;
    };
  };
};
