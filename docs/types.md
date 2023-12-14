# types

## Type `ChunkMessage`
``` motoko no-repl
type ChunkMessage<T> = (length : Nat, {#chunk : [T]; #ping})
```

Argument of processing function.

## Type `ControlMessage`
``` motoko no-repl
type ControlMessage = {#ok; #gap; #stop}
```

Return type of processing function.
