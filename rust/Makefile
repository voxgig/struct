.PHONY: inspect build test bench lint clippy fmt-check clean reset audit publish

inspect:
	@echo "Rust toolchain:"
	@rustc --version
	@cargo --version
	@echo ""
	@echo "Project version:"
	@grep '^version' Cargo.toml | head -1

build:
	cargo build

test:
	cargo test

# Cross-port performance harness (JSON contract; see build/bench/README.md).
# --release for realistic numbers; -q keeps cargo's build chatter off stdout.
bench:
	@BENCH_RUSTC="$$(rustc --version | cut -d' ' -f1,2)" cargo run -q --release --example bench

# Code quality: Clippy (treat warnings as errors) + rustfmt check.
lint: clippy fmt-check

clippy:
	cargo clippy --all-targets --all-features -- -D warnings

fmt-check:
	cargo fmt --all -- --check

clean:
	cargo clean

reset: clean
	rm -f Cargo.lock

# Supply-chain: scan Cargo dependencies against the RustSec advisory DB.
audit:
	cargo audit

# Release: publish to crates.io, then tag rust/vX.Y.Z (version from Cargo.toml).
# Needs crates.io auth (CARGO_REGISTRY_TOKEN / `cargo login`). Dry-run with:
#   cargo publish --dry-run
VERSION := $(shell grep -m1 '^version' Cargo.toml | sed -E 's/.*"([^"]+)".*/\1/')
TAG := rust/v$(VERSION)
AQL_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump Cargo.toml first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(AQL_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] aql filler token detected: would publish crate and tag $(TAG); nothing pushed."; \
	  exit 0; \
	fi; \
	cargo publish; \
	git tag -a "$(TAG)" -m "rust v$(VERSION)"; \
	if [ -n "$$token" ]; then \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$token" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Published crate + tag $(TAG)."
