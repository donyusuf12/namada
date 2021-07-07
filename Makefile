package = anoma

cargo := $(env) cargo
rustup := $(env) rustup
debug-env := RUST_BACKTRACE=1 RUST_LOG=$(package)=debug
debug-cargo := $(env) $(debug-env) cargo
# Nightly build is currently used for rustfmt and clippy.
nightly := $(shell cat rust-nightly-version)

# Paths for all the wasm sources
tx_wasms := $(dir $(wildcard wasm/txs/*/.))
vp_wasms := $(dir $(wildcard wasm/vps/*/.))	
wasms := $(tx_wasms) $(vp_wasms) wasm/matchmaker_template wasm/filter_template

# Transitive dependency of wasmer. It's safe to ignore as we don't use cranelift compiler. It should disseaper once the wasmer library updates its dependencies
audit-ignores := RUSTSEC-2021-0067
# Transitive dependency warning from tendermint-rpc
audit-ignores += RUSTSEC-2021-0064
# Transitive dependency warning from tendermint-rpc
audit-ignores += RUSTSEC-2020-0016

build:
	$(cargo) build

build-test:
	$(cargo) build --tests

build-release:
	$(cargo) build --release

check-wasm = $(cargo) check --target wasm32-unknown-unknown --manifest-path $(wasm)/Cargo.toml
check:
	$(cargo) check && \
	$(foreach wasm,$(wasms),$(check-wasm) && ) true

clippy-wasm = $(cargo) +$(nightly) clippy --manifest-path $(wasm)/Cargo.toml --all-targets -- -D warnings
clippy:
	$(cargo) +$(nightly) clippy --all-targets -- -D warnings && \
	$(foreach wasm,$(wasms),$(clippy-wasm) && ) true

install:
	# Warning: built in debug mode for now
	$(cargo) install --path ./apps --debug

run-ledger:
	# runs the node
	$(cargo) run --bin anoman -- ledger run

run-gossip:
	# runs the node gossip node
	$(cargo) run --bin anoman -- gossip run

reset-ledger:
	# runs the node
	$(cargo) run --bin anoman -- ledger reset

audit:
	$(cargo) audit $(foreach ignore,$(audit-ignores), --ignore $(ignore))

test-wasm = $(cargo) test --manifest-path $(wasm)/Cargo.toml
test:
	make test-unit && \
	make test-e2e && \
	make test-wasm

test-e2e:
	$(cargo) test e2e -- --test-threads=1

test-unit:
	$(cargo) test -- --skip e2e

test-wasm = $(cargo) test --manifest-path $(wasm)/Cargo.toml
test-wasm:
	$(foreach wasm,$(wasms),$(test-wasm) && ) true

test-debug:
	$(debug-cargo) test -- --nocapture

fmt-wasm = $(cargo) +$(nightly) fmt --manifest-path $(wasm)/Cargo.toml
fmt:
	$(cargo) +$(nightly) fmt --all && \
	$(foreach wasm,$(wasms),$(fmt-wasm) && ) true

fmt-check-wasm = $(cargo) +$(nightly) fmt --manifest-path $(wasm)/Cargo.toml -- --check
fmt-check:
	$(cargo) +$(nightly) fmt --all -- --check && \
	$(foreach wasm,$(wasms),$(fmt-check-wasm) && ) true

watch:
	$(cargo) watch

clean:
	$(cargo) clean

build-doc:
	$(cargo) doc --no-deps
	make -C tech-specs build

doc:
	# build and opens the docs in browser
	$(cargo) doc --open

build-wasm-scripts-docker:
	docker run --rm -v ${PWD}:/usr/local/rust/project anoma-wasm make build-wasm-scripts

# Build the validity predicate, transactions, matchmaker and matchmaker filter wasm
build-wasm = make -C $(wasm)
build-wasm-scripts:
	$(foreach wasm,$(wasms),$(build-wasm) && ) true

clean-wasm = make -C $(wasm)
clean-wasm-scripts:
	$(foreach wasm,$(wasms),$(clean-wasm) && ) true

dev-deps:
	$(rustup) toolchain install $(nightly)
	$(rustup) target add wasm32-unknown-unknown
	$(rustup) component add rustfmt clippy miri --toolchain $(nightly)
	$(cargo) install cargo-watch

test-miri:
	$(cargo) +$(nightly) miri setup
	$(cargo) +$(nightly) clean
	MIRIFLAGS="-Zmiri-disable-isolation" $(cargo) +$(nightly) miri test

.PHONY : build check build-release clippy install run-ledger run-gossip reset-ledger test test-debug fmt watch clean build-doc doc build-wasm-scripts-docker build-wasm-scripts clean-wasm-scripts dev-deps test-miri
