module {
  public type ChunkMessage<T> = (
    Nat,
    {
      #chunk : [T];
      #ping;
    },
  );
  public type ControlMessage = { #ok; #gap; #stop };
};
