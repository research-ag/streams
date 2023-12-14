module {
  /// Argument of processing function.
  public type ChunkMessage<T> = (
    Nat,
    {
      #chunk : [T];
      #ping;
    },
  );
  /// Return type of processing function.
  public type ControlMessage = { #ok; #gap; #stop };
};
