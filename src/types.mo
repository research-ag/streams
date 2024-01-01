module {
  /// Type of messages sent to the receiver
  public type ChunkMessage<T> = (
    pos : Nat,
    {
      #chunk : [T];
      #ping;
      #restart;
    },
  );

  public type ChunkPayload<T> = {
    #chunk : [T];
    #ping;
  };

  /// Information passed to callback
  public type ChunkInfo = {
    #chunk : Nat;
    #ping;
  };

  public func info(m : ChunkPayload<Any>) : ChunkInfo {
    switch m {
      case (#chunk c) #chunk(c.size());
      case (#ping) #ping;
    };
  };

  /// Return type of processing function.
  public type ControlMessage = { #ok; #gap; #stop };
};
