module {
  public type ChunkMsg<T> = (
    Nat,
    {
      #chunk : [T];
      #ping;
    },
  );
  public type ControlMsg = { #ok; #gap; #stop };
}