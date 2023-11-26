import Debug "mo:base/Debug";
import Error "mo:base/Error";
import R "mo:base/Result";
import Time "mo:base/Time";
import Array "mo:base/Array";
import Option "mo:base/Option";
import SWB "mo:swb";

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
  public type Chunk<S> = (Nat, [S]);

  // T = queue item type
  // S = stream item type
  public class StreamSender<T, S>(
    counterCreator : () -> { accept(item : T) : Bool },
    wrapItem : T -> S,
    sendFunc : (x : Chunk<S>) -> async* Bool,
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

    var closed = false;
    var paused = false;
    var head = 0;
    var lastChunkSent = Time.now();
    var concurrentChunks = 0;

    func isQueueFull() : Bool = switch (settings_.maxQueueSize) {
      case (?max) buffer.len() >= max;
      case (null) false;
    };

    /// add item to the stream
    public func queue(item : T) : {
      #ok : Nat;
      #err : { #NoSpace };
    } {
      if (isQueueFull())
      #err(#NoSpace) else
      #ok(buffer.add(item));
    };

    /// send chunk to the receiver
    public func sendChunk() : async* () {
      if (isClosed()) Debug.trap("Stream closed");
      if (isBusy()) Debug.trap("Stream sender is busy");
      if (isPaused()) Debug.trap("Stream sender is paused");

      func chunk() : (Nat, Nat, [S]) {
        var start = head;
        var end = start;
        let counter = counterCreator();
        label peekLoop while (true) {
          switch (buffer.getOpt(end)) {
            case (null) break peekLoop;
            case (?item) {
              if (not counter.accept(item)) break peekLoop;
              end += 1;
            };
          };
        };
        func pop() : T {
          let ?x = buffer.getOpt(head) else Debug.trap("queue empty in pop()");
          head += 1;
          x;
        };
        let elements = Array.tabulate<S>(end - start, func(n) = wrapItem(pop()));
        (start, end, elements);
      };

      let (start, end, elements) = chunk();

      func shouldPing() : Bool {
        switch (settings_.keepAliveSeconds) {
          case (?i) lastChunkSent + i * 1_000_000_000 < Time.now();
          case (null) false;
        };
      };

      if (start == end and not shouldPing()) return;

      func receive() {
        concurrentChunks -= 1;
        if (concurrentChunks == 0 and paused) {
          head := buffer.start();
          paused := false;
        };
      };

      lastChunkSent := Time.now();
      concurrentChunks += 1;

      let success = try {
        let chunk = (start, elements);
        await* sendFunc(chunk);
      } catch (e) {
        paused := true;
        receive();
        throw e;
      };

      buffer.deleteTo(if success { end } else { start });
      receive();

      if (not success) {
        closed := true;
      };
    };

    /// total amount of items, ever added to the stream sender, also an index, which will be assigned to the next item
    public func length() : Nat = buffer.end();

    /// amount of items, which were sent to receiver
    public func sent() : Nat = head;

    /// amount of items, successfully sent and acknowledged by receiver
    public func received() : Nat = buffer.start();

    /// get item from queue by index
    public func get(index : Nat) : ?T = buffer.getOpt(index);

    /// check busy status of sender
    public func isBusy() : Bool {
      concurrentChunks == Option.get(settings_.maxConcurrentChunks, MAX_CONCURRENT_CHUNKS_DEFAULT);
    };

    /// check busy level of sender, e.g. current amount of outgoing calls in flight
    public func busyLevel() : Nat = concurrentChunks;

    /// returns flag is receiver closed the stream
    public func isClosed() : Bool = closed;

    /// check paused status of sender
    public func isPaused() : Bool = paused;

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
