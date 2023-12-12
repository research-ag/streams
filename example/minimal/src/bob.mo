import Stream "mo:streams/StreamReceiver";
import Error "mo:base/Error";

actor class Main (sender : Principal) {
  // substitute your item type here
  type Item = Nat; 

  // define your processing function
  var log_ : Text = "";
  func processItem(index : Nat, item : Item) : () { // choose function name, keep the signature
    log_ #= debug_show (index,item) # " "; // put your processing code here
  };

  // begin boilerplate
  let receiver_ = Stream.StreamReceiver<Item>(0, null, processItem); // use your processing function name here
  public shared (msg) func receive(m : Stream.ChunkMessage<Item>) : async Stream.ControlMessage { // choose a name for public endpoint
    if (msg.caller != sender) throw Error.reject("not authorized"); // use your sender argument here 
    receiver_.onChunk(m); // ok to wrap custom code around this
  };
  // end boilerplate

  public func log() : async Text { log_ };
};
