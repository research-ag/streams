# StreamReceiver

## Type `ControlMessage`
``` motoko no-repl
type ControlMessage = Types.ControlMessage
```

Usage:

let receiver = StreamReceiver<Int>(
  123
  func (streamId : Nat, element: Int, index: Nat): () {
    ... do your logic with incoming item
  }
);

Hook-up receive function in the actor class:
public shared func onStreamChunk(streamId : Nat, chunk: [Int], firstIndex: Nat) : async () {
  switch (streamId) case (123) { await receiver.onChunk(chunk, firstIndex); }; case (_) { Error.reject("Unknown stream"); }; };
};

The function `onChunk` throws in case of a gap (= broken pipe). The
calling code should not catch the throw so that it gets passed through to
the enclosing async expression of the calling code.

## Type `ChunkMessage`
``` motoko no-repl
type ChunkMessage<T> = Types.ChunkMessage<T>
```


## Type `StableData`
``` motoko no-repl
type StableData = (Nat, Int)
```


## Class `StreamReceiver<T>`

``` motoko no-repl
class StreamReceiver<T>(startPos : Nat, timeout : ?Nat, itemCallback : (pos : Nat, item : T) -> ())
```


### Function `share`
``` motoko no-repl
func share() : StableData
```



### Function `unshare`
``` motoko no-repl
func unshare(data : StableData)
```



### Function `onChunk`
``` motoko no-repl
func onChunk(cm : Types.ChunkMessage<T>) : Types.ControlMessage
```

processes a chunk and responds to sender


### Function `stop`
``` motoko no-repl
func stop()
```



### Function `length`
``` motoko no-repl
func length() : Nat
```



### Function `lastChunkReceived`
``` motoko no-repl
func lastChunkReceived() : Int
```

returns timestamp when stream received last chunk


### Function `stopped`
``` motoko no-repl
func stopped() : Bool
```

returns flag if receiver timed out because of non-activity
