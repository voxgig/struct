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

# The corpus harness is a separate package (`corpus/`) so that omni stays out
# of the library's manifest entirely - Cargo resolves dev-dependencies even
# for `cargo build`, so a dev-dependency here would break a checkout with no
# omni beside it. Register 4.13; the same shape as struct/go's nested module.
#
# No omni prerequisite any more: corpus/Cargo.toml takes omni from its release
# tag, `rust/v0.1.0`, and corpus/Cargo.lock pins the commit that tag resolved
# to. Nothing here needs a checkout beside it, and nothing here can silently
# test against a different omni than the lockfile records.
test:
	cargo test
	cd corpus && cargo test

# Cross-port performance harness (JSON contract; see build/bench/README.md).
# --release for realistic numbers; -q keeps cargo's build chatter off stdout.
bench:
	@BENCH_RUSTC="$$(rustc --version | cut -d' ' -f1,2)" cargo run -q --release --example bench

# Code quality: Clippy (treat warnings as errors) + rustfmt check.
lint: clippy fmt-check

clippy:
	cargo clippy --all-targets --all-features -- -D warnings
	cd corpus && cargo clippy --all-targets --all-features -- -D warnings

# `-p`, not `--all`: corpus is its own workspace root and its dependencies
# (`..` and omni) are in the graph, so `--all` reformats voxgig/omni's sources
# and fails on THEIR style. Scope it to this package.
fmt-check:
	cargo fmt --all -- --check
	cd corpus && cargo fmt -p voxgig-struct-corpus -- --check

clean:
	cargo clean

reset: clean
	rm -f Cargo.lock

# Supply-chain: scan Cargo dependencies against the RustSec advisory DB.
audit:
	cargo audit

# Release: publish to crates.io, then tag rust/vX.Y.Z (version from Cargo.toml).
#
# PREFER THE WORKFLOW. crates.io has a trusted publisher registered against
# .github/workflows/publish.yml, so the supported path is
#
#   Actions -> publish -> Run workflow, on main, with target: rust
#
# which publishes over a short-lived OIDC token and cuts the SAME
# rust/vX.Y.Z tag this target does. `dry_run: true` rehearses it without
# releasing. This target remains for the case where CI cannot run, and it
# publishes over a long-lived CARGO_REGISTRY_TOKEN / `cargo login`
# credential instead - no OIDC, no provenance. Rehearse it locally with:
#   cargo publish --dry-run
VERSION := $(shell grep -m1 '^version' Cargo.toml | sed -E 's/.*"([^"]+)".*/\1/')
TAG := rust/v$(VERSION)
# (The literal keeps the legacy AQL name: it must match the boru vault's dryRunFiller constant.)
BORU_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump Cargo.toml first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(BORU_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] boru filler token detected: would publish crate and tag $(TAG); nothing pushed."; \
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
