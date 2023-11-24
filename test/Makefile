MOPS_PKGS=$(shell mops sources)

all: StreamSender StreamReceiver

StreamSender:
	moc $(MOPS_PKGS) -wasi-system-api StreamSender.mo && wasmtime StreamSender.wasm

StreamReceiver:
	moc $(MOPS_PKGS) -wasi-system-api StreamReceiver.mo && wasmtime StreamReceiver.wasm
