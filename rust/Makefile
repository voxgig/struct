.PHONY: inspect build test lint clippy fmt-check clean reset audit publish

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
publish: test
	cargo publish
	@if git rev-parse -q --verify "refs/tags/rust/v$(VERSION)" >/dev/null; then \
	  echo "tag rust/v$(VERSION) already exists — bump Cargo.toml version first"; exit 1; fi
	git tag -a "rust/v$(VERSION)" -m "rust v$(VERSION)"
	git push origin "rust/v$(VERSION)"
