#!/usr/local/bin/ic-repl

let receiver = call ic.provisional_create_canister_with_cycles(record { settings = null; amount = null });
let receiver_canister = receiver.canister_id;
let sender = call ic.provisional_create_canister_with_cycles(record { settings = null; amount = null });
let sender_canister = sender.canister_id;

call ic.install_code(
  record {
    arg = encode ();
    wasm_module = file(".dfx/local/canisters/receiver/receiver.wasm");
    mode = variant { install };
    canister_id = receiver_canister;
  },
);
call ic.install_code(
  record {
    arg = encode ( receiver_canister );
    wasm_module = file(".dfx/local/canisters/sender/sender.wasm");
    mode = variant { install };
    canister_id = sender_canister;
  },
);

identity user;
call sender_canister.add("abc");
call receiver_canister.lastReceived();
call sender_canister.add("def");
call receiver_canister.lastReceived();
call sender_canister.add("ghi");
call receiver_canister.lastReceived();
call sender_canister.add("jkl");
call receiver_canister.lastReceived();
call sender_canister.add("mno");
call receiver_canister.lastReceived();
call sender_canister.add("pqr");
call receiver_canister.lastReceived();