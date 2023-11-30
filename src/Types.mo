module {
  public type ChunkMsg<S> = (
    startPos : Nat,
    {
      #chunk : [S];
      #ping;
    },
  );
  public type ControlMsg = { #stopped; #ok; #gap };
};
