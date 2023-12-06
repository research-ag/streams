module {
  public type ChunkMsg<T> = (
    Nat,
    {
      #chunk : [T];
      #ping;
    },
  );
  // public type ChunkMsg<T> = {
  //   #chunk : (Nat, [T]);
  //   #ping;
  // };
  public type ControlMsg = { #ok; #gap; #stop };
};
