#!/usr/local/bin/ic-repl

let alice = call ic.provisional_create_canister_with_cycles(record { settings = null; amount = null });
let bob = call ic.provisional_create_canister_with_cycles(record { settings = null; amount = null });

let _ = call ic.install_code(
  record {
    arg = encode ( bob.canister_id );
    wasm_module = file(".dfx/local/canisters/alice/alice.wasm");
    mode = variant { install };
    canister_id = alice.canister_id;
  },
);
let _ = call ic.install_code(
  record {
    arg = encode ( alice.canister_id );
    wasm_module = file(".dfx/local/canisters/bob/bob.wasm");
    mode = variant { install };
    canister_id = bob.canister_id;
  },
);

identity user;
let a = alice.canister_id;
let b = bob.canister_id;
let _ = call a.enqueue(7);
call b.log();
let _ = call a.batch(); call b.log();
let _ = call a.batch(); call b.log();
let _ = call a.batch(); call b.log();
let _ = call a.batch(); call b.log();
