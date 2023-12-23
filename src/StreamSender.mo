import Error "mo:base/Error";
import Option "mo:base/Option";
import Nat "mo:base/Nat";
import Result "mo:base/Result";
import SWB "mo:swb";
import Vector "mo:vector";
import Types "types";

module {
  /// Status of `StreamSender`.
  public type Status = { #shutdown; #stopped; #paused; #busy; #ready };

  /// Return type of processing function.
  public type ControlMessage = Types.ControlMessage;

  /// Argument of processing function.
  public type ChunkMessage<T> = Types.ChunkMessage<T>;

  /// Maximum concurrent chunks number.
  public let MAX_CONCURRENT_CHUNKS_DEFAULT = 5;

  /// Settings of `StreamSender`.
  public type Settings = {
    maxQueueSize : ?Nat;
    maxConcurrentChunks : ?Nat;
    keepAlive : ?(Nat, () -> Int);
  };

  /// Type of `StableData` for `share`/`unshare` function.
  public type StableData<T> = {
    buffer : SWB.StableData<T>;
    stopped : Bool;
    //    paused : Bool;
    head : Nat;
    lastChunkSent : Int;
    //    concurrentChunks : Nat;
    shutdown : Bool;
  };
  /// Stream sender receiving items of type `T` with `push` function and sending them with `sendFunc` callback when calling `sendChunk`.
  ///
  /// Arguments:
  /// * `sendFunc` typically should implement sending chunk to the receiver canister.
  /// * `counterCreator` is used to create a chunk out of pushed items.
  /// `accept` function is called sequentially on items which are added to the chunk, until receiving `null`.
  /// If the item is accepted it should be converted to type `S`.
  /// Typical implementation of `counter` is to accept items while their total size is less then given maximum chunk size.
  /// * `settings` consists of:
  ///   * `maxQueueSize` is maximum number of elements, which can simultaneously be in `StreamSender`'s queue. Default value is infinity.
  ///   * `maxConcurrentChunks` is maximum number of concurrent `sendChunk` calls. Default value is `MAX_CONCURRENT_CHUNKS_DEFAULT`.
  ///   * `keepAlive` is pair of period in seconds after which `StreamSender` should send ping chunk in case if there is no items to send and current time function.
  ///     Default value means not to ping.
  public class StreamSender<T, S>(
    counterCreator : () -> { accept(item : T) : ?S },
    sendFunc : (x : Types.ChunkMessage<S>) -> async* Types.ControlMessage,
    settings : ?Settings,
  ) {
    let buffer = SWB.SlidingWindowBuffer<T>();

    var settings_ = {
      var maxQueueSize = Option.chain<Settings, Nat>(settings, func s = s.maxQueueSize);
      var maxConcurrentChunks = Option.chain<Settings, Nat>(settings, func s = s.maxConcurrentChunks);
      var keepAlive = Option.chain<Settings, (Nat, () -> Int)> (settings, func s = s.keepAlive);
    };

    var stopped = false;
    var paused = false;
    var head : Nat = 0;
    var lastChunkSent : Int = 0;
    var concurrentChunks = 0;
    var shutdown = false;

    func updateTime() {
      let ?arg = settings_.keepAlive else return;
      lastChunkSent := arg.1 ();
    };

    updateTime();

    /// Share data in order to store in stable varible. No validation is performed.
    public func share() : StableData<T> = {
      buffer = buffer.share();
      stopped = stopped;
      //      paused = paused;
      head = head;
      lastChunkSent = lastChunkSent;
      //      concurrentChunks = concurrentChunks;
      shutdown = shutdown;
    };

    /// Unhare data in order to store in stable varible. No validation is performed.
    public func unshare(data : StableData<T>) {
      buffer.unshare(data.buffer);
      stopped := data.stopped;
      //      paused := data.paused;
      head := data.head;
      lastChunkSent := data.lastChunkSent;
      //      concurrentChunks := data.concurrentChunks;
      shutdown := data.shutdown;
    };

    func isQueueFull() : Bool {
      let ?max = settings_.maxQueueSize else return false;
      return buffer.len() >= max;
    };

    /// Add item to the `StreamSender`'s queue. Return number of succesfull `push` call, or error in case of lack of space.
    public func push(item : T) : Result.Result<Nat, { #NoSpace }> {
      if (isQueueFull()) #err(#NoSpace) else
      #ok(buffer.add(item));
    };

    /// Get the stream sender's status for inspection.
    ///
    /// The function is sychronous. It can be used (optionally) by the user of
    /// the class before calling the asynchronous function sendChunk.
    ///
    /// sendChunk will attempt to send a chunk if and only if the status is
    /// `#ready`.  sendChunk will throw if and only if the status is `#shutdown`, `#stopped`,
    /// `#paused` or `#busy`.
    ///
    /// `#shutdown` means irrecoverable error ocurred during the work process of `StreamSender`.
    ///
    /// `#stopped` means that the stream sender was stopped by the receiver, e.g.
    /// due to a timeout.
    ///
    /// `#paused` means that at least one chunk could not be delivered and the
    /// stream sender is waiting for outstanding responses to come back before
    /// it can resume sending chunks. When it resumes it will start from the
    /// first item that did not arrive.
    ///
    /// `#busy` means that there are too many chunk concurrently in flight. The
    /// sender is waiting for outstanding responses to come back before sending
    /// any new chunks.
    ///
    /// `#ready` means that the stream sender is ready to send a chunk.

    public func status() : Status {
      if (shutdown) return #shutdown;
      if (stopped) return #stopped;
      if (paused) return #paused;
      if (isBusy()) return #busy;
      return #ready;
    };

    /// Send chunk to the receiver.
    ///
    /// A return value `()` means that the stream sender was ready to send the
    /// chunk and attempted to send it. It does not mean that the chunk was
    /// delivered to the receiver.
    ///
    /// If the stream sender is not ready (shutdown, stopped, paused or busy) then the
    /// function throws immediately and does not attempt to send the chunk.
    public func sendChunk() : async* () {
      if (shutdown) throw Error.reject("Sender shut down");
      if (stopped) throw Error.reject("Stream stopped by receiver");
      if (paused) throw Error.reject("Stream is paused");
      if (isBusy()) throw Error.reject("Stream is busy");

      let start = head;
      let elements = do {
        var end = head;
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
        head := end;
        Vector.toArray(vec);
      };

      let size = elements.size();

      func shouldPing() : Bool {
        let ?arg = settings_.keepAlive else return false;
        return (arg.1 () - lastChunkSent) > arg.0;
      };

      if (size == 0 and not shouldPing()) return;

      let msg = if (size > 0) #chunk elements else #ping;

      updateTime();
      concurrentChunks += 1;

      let res = try {
        await* sendFunc((start, msg));
      } catch (e) {
        // shutdown on permanent system errors
        switch (Error.code(e)) {
          case (#system_fatal or #destination_invalid or #future _) shutdown := true;
          case (_) {};
          // TODO: revisit #canister_reject after an IC protocol bug is fixed.
          // Currently, a stopped receiver responds with #canister_reject.
          // In the future it should be #canister_error.
          //
          // However, there is an advantage of handling #canister_reject and
          // #canister_error equally. It becomes easier to test because in the
          // moc interpreter we can simulate #canister_reject but not
          // #canister_error.
        };
        #error;
      };

      // planned changes
      var ok = buffer.start();
      var retrace = head;
      var retraceMoreLater = false;
      var pausing = false;

      let end = start + size;

      switch (res) {
        case (#ok) { ok := end };
        case (#gap) { retrace := start; retraceMoreLater := true };
        case (#stop) { ok := start; retrace := start };
        case (#error) if (start != end) { retrace := start };
      };

      if (res != #ok) pausing := true;

      // protocol-level assertions (are covered in tests)
      func assert_(condition : Bool) = if (not condition) shutdown := true;
      assert_(ok <= head);
      assert_(buffer.start() <= retrace);
      if (retraceMoreLater) assert_(buffer.start() < retrace);

      // internal assertions (not covered in tests, would represent an internal bugs if triggered)
      if (retrace < head) assert_(end <= head);
      if (not paused and pausing) assert_(retrace <= head);

      // apply changes
      buffer.deleteTo(ok);
      head := Nat.min(head, retrace);
      if (pausing) paused := true;

      // unpause stream
      concurrentChunks -= 1;
      if (concurrentChunks == 0) {
        paused := false;
      };

      // stop stream
      if (res == #stop) stopped := true;
    };

    /// Restart the sender in case it's stopped after receiving `#stop` from `sendFunc`.
    public func restart() : async Bool {
      if (shutdown) return false;
      if (paused) return false;
      let res = try {
        await* sendFunc((head, #restart));
      } catch (_) { #error };
      switch (res) {
        case (#ok) { stopped := false; true };
        case (#gap or #stop or #error) false;
      };
    };

    /// Total amount of items, ever added to the stream sender, also an index, which will be assigned to the next item
    public func length() : Nat = buffer.end();

    /// Amount of items, which were sent to receiver.
    public func sent() : Nat = head;

    /// Amount of items, successfully sent and acknowledged by receiver.
    public func received() : Nat = buffer.start();

    /// Get item from queue by index.
    public func get(index : Nat) : ?T = buffer.getOpt(index);

    /// Returns flag is sender is ready.
    public func isReady() : Bool = status() == #ready;

    /// Returns flag is sender has shut down.
    public func isShutdown() : Bool = shutdown;

    /// Returns flag is receiver stopped the stream.
    public func isStopped() : Bool = stopped;

    /// Check busy status of sender.
    public func isBusy() : Bool {
      concurrentChunks == Option.get(
        settings_.maxConcurrentChunks,
        MAX_CONCURRENT_CHUNKS_DEFAULT,
      );
    };

    /// Check busy level of sender, e.g. current amount of outgoing calls in flight.
    public func busyLevel() : Nat = concurrentChunks;

    /// Check paused status of sender.
    public func isPaused() : Bool = paused;

    /// Update max queue size.
    public func setMaxQueueSize(value : ?Nat) {
      settings_.maxQueueSize := value;
    };

    /// Update max amount of concurrent outgoing requests.
    public func setMaxConcurrentChunks(value : ?Nat) {
      settings_.maxConcurrentChunks := value;
    };

    /// Update max interval between stream calls.
    public func setKeepAlive(seconds : ?(Nat, () -> Int)) {
      settings_.keepAlive := seconds;
    };
  };
};
