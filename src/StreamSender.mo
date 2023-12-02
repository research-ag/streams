import Debug "mo:base/Debug";
import Error "mo:base/Error";
import R "mo:base/Result";
import Time "mo:base/Time";
import Array "mo:base/Array";
import Option "mo:base/Option";
import SWB "mo:swb";
import Vector "mo:vector";

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
  public type ChunkMsg<S> = (
    startPos : Nat,
    {
      #chunk : [S];
      #ping;
    },
  );
  public type ControlMsg = { #stopped; #ok; #gap };
  public type Status = { #stopped; #paused; #busy; #ready : Nat };
  public type ChunkResponse = { #ok; #gap; #stopped; #error : Error.ErrorCode};

  // T = queue item type
  // S = stream item type
  public class StreamSender<T, S>(
    counterCreator : () -> { accept(item : T) : ?S },
    sendFunc : (x : ChunkMsg<S>) -> async* ControlMsg,
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

    /// Get the stream sender's status for inspection.
    ///
    /// The function is sychronous. It can be used (optionally) by the user of
    /// the class before calling the asynchronous function sendChunk.
    ///
    /// sendChunk will attempt to send a chunk if and only if the status is
    /// #ready.  sendChunk will throw if and only if the status is #stopped,
    /// #paused or #busy.
    ///
    /// #stopped means that the stream sender was stopped by the receiver, e.g.
    /// due to a timeout.
    ///
    /// #paused means that at least one chunk could not be delivered and the
    /// stream sender is waiting for outstanding responses to come back before
    /// it can resume sending chunks. When it resumes it will start from the
    /// first item that did not arrive.
    ///
    /// #busy means that there are too many chunk concurrently in flight. The
    /// sender is waiting for outstanding responses to come back before sending
    /// any new chunks.
    ///
    /// #ready n means that the stream sender is ready to send a chunk starting
    /// from position n.

    public func status() : Status {
      if (isStopped()) return #stopped;
      let ?start = head else return #paused;
      if (isBusy()) return #busy;
      return #ready start;
    };


    var lastResponse_ : ChunkResponse = #ok;
    public func lastResponse() : ChunkResponse = lastResponse_;

    /// Send chunk to the receiver
    ///
    /// A return value () means that the stream sender was ready to send the
    /// chunk and attempted to send it. It does not mean that the chunk was
    /// delivered to the receiver.
    ///
    /// If the stream sender is not ready (stopped, paused or busy) then the
    /// function throws immediately and does not attempt to send the chunk.

    public func sendChunk() : async* () {
      let start = switch (status()) {
        case (#stopped) throw Error.reject("Stream stopped by receiver");
        case (#paused) throw Error.reject("Stream is paused");
        case (#busy) throw Error.reject("Stream is busy");
        case (#ready x) x;
      };

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
        if (not shouldPing()) return;
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

      try {
        switch (await* sendFunc(chunkMsg)) {
          case (#ok) {
            buffer.deleteTo(end);
            lastResponse_ := #ok;
          };
          case (#stopped) {
            stopped := true;
            buffer.deleteTo(start);
            lastResponse_ := #stopped;
          };
          case (#gap) {
            head := null;
            lastResponse_ := #gap;
          };
        };
      } catch (e) {
        head := null;
        lastResponse_ := #error (Error.code(e));
      };
      receive();
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
