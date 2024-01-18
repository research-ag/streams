module {
  public type ChunkPayload<T> = { #chunk : [T]; #ping };
  public type ChunkInfo = { #chunk : Nat; #ping };
  public func chunkInfo(m : ChunkPayload<Any>) : ChunkInfo {
    switch m {
      case (#chunk c) #chunk(c.size());
      case (#ping) #ping;
    };
  };

  /// Type of messages sent to the receiver
  /// (stream position, chunk payload)
  public type ChunkMessage<T> = (Nat, ChunkPayload<T> or { #restart });
  public type ChunkMessageInfo = (Nat, ChunkInfo or { #restart });
  public func chunkMessageInfo(m : ChunkMessage<Any>) : ChunkMessageInfo {
    (
      m.0,
      switch (m.1) {
        case (#chunk c) #chunk(c.size());
        case (#ping) #ping;
        case (#restart) #restart;
      },
    );
  };

  /// Return type of processing function.
  public type ControlMessage = { #ok; #gap; #stop : Nat };
};
