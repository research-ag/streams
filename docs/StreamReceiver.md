# StreamReceiver

## Type `ControlMessage`
``` motoko no-repl
type ControlMessage = Types.ControlMessage
```

Return type of processing function.

## Type `ChunkMessage`
``` motoko no-repl
type ChunkMessage<T> = Types.ChunkMessage<T>
```

Argument of processing function.

## Type `StableData`
``` motoko no-repl
type StableData = (Nat, Int)
```

Type of `StableData` for `share`/`unshare` function.

## Class `StreamReceiver<T>`

``` motoko no-repl
class StreamReceiver<T>(startPos : Nat, timeout : ?Nat, itemCallback : (pos : Nat, item : T) -> ())
```

Stream recevier receiving chunks on `onChunk` call,
validating whether `length` in chunk message corresponds to `length` inside `StreamRecevier`,
calling `itemCallback` on each items of the chunk.

Arguments:
* `startPos` is starting length.
* `timeout` is maximum time between onChunk calls. Default time period is infinite.
* `itemCallback` function to be called on each received item.

### Function `share`
``` motoko no-repl
func share() : StableData
```

Share data in order to store in stable varible. No validation is performed.


### Function `unshare`
``` motoko no-repl
func unshare(data : StableData)
```

Unhare data in order to store in stable varible. No validation is performed.


### Function `onChunk`
``` motoko no-repl
func onChunk(cm : Types.ChunkMessage<T>) : Types.ControlMessage
```

Returns `#gap` if length in chunk don't correspond to length in `StreamReceiver`.
Returns `#stopped` if the receiver is already stopped or maximum time out between chunks exceeded.
Otherwise processes a chunk and call `itemCallback` on each item.


### Function `stop`
``` motoko no-repl
func stop()
```

Manually stop the receiver.


### Function `length`
``` motoko no-repl
func length() : Nat
```

Current number of received items.


### Function `lastChunkReceived`
``` motoko no-repl
func lastChunkReceived() : Int
```

Returns timestamp when stream received last chunk


### Function `stopped`
``` motoko no-repl
func stopped() : Bool
```

Returns flag if receiver timed out because of non-activity or stopped.
