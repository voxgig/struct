# Makefile for the Lean 4 port of voxgig/struct.
# Requires the Lean toolchain (elan provides `lake`/`lean`; the version is
# pinned by ./lean-toolchain). No third-party libraries.

# elan installs to ~/.elan/bin; prepend it so a stock elan install just works.
export PATH := $(HOME)/.elan/bin:$(PATH)

.PHONY: test bench lint build inspect clean reset publish omni-check

# The corpus runner is voxgig/omni, consumed as a local checkout - it is not
# published. $OMNI_HOME first, then sibling paths, taking the first directory
# that carries spec/fib.json.
#
# COPIED in rather than built in place: lake writes its olean beside the
# source, and the checkout is not ours to litter (nor necessarily writable).
# lakefile.toml declares `.omni-build` as a lean_lib that only the RUNNER
# imports, so `make build` compiles the library alone (register 4.13).
OMNI_CANDIDATES := $(OMNI_HOME) ../../omni ../../../omni /workspace/omni /home/user/omni
OMNI_DIR := $(firstword $(foreach d,$(OMNI_CANDIDATES),$(if $(wildcard $(d)/spec/fib.json),$(d))))

omni-check:
	@if [ -z "$(OMNI_DIR)" ]; then \
	  echo "struct: voxgig/omni checkout not found - set OMNI_HOME."; \
	  echo "  The tests run on the shared runner; the library itself does not."; \
	  echo "  git clone https://github.com/voxgig/omni ../../omni"; \
	  exit 1; \
	fi
	@mkdir -p .omni-build
	@cp $(OMNI_DIR)/lean/Omni.lean .omni-build/Omni.lean

# Build and run the shared JSON corpus through the Lean implementation, on
# voxgig/omni.
test: omni-check
	lake build runner
	./.lake/build/bin/runner ../build/test/test.json

# The LIBRARY alone: nothing shipped names omni (register 4.13).
build:
	lake build VoxgigStruct

# "Lint": type-check the library (a clean compile means it is sound; the
# build is warnings-clean). No third-party linter exists for Lean.
# The runner imports omni, so this needs the checkout too.
lint: omni-check
	lake build
	@echo ok

bench:
	@echo "(no bench harness wired for the lean port yet)"

inspect:
	@lean --version

clean:
	rm -rf .lake

reset: clean

# Release: Lean has no publish flow wired here beyond the git tag — the port
# lives in a monorepo subdirectory, which the Reservoir registry cannot index
# directly, so publishing IS the git tag (like the Zig and Go ports).
# Auth: GITHUB_TOKEN (or GH_TOKEN) for HTTPS tag push; ssh `origin` otherwise.
VERSION := $(shell cat VERSION)
TAG := lean/v$(VERSION)
# (The literal keeps the legacy AQL name: it must match the boru vault's dryRunFiller constant.)
BORU_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump lean/VERSION first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(BORU_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] boru filler token detected: would tag $(TAG) and push it over"; \
	  echo "[dry-run] HTTPS to github.com/voxgig/struct — no tag created, nothing pushed."; \
	  exit 0; \
	fi; \
	echo "tag: $(TAG)"; \
	git tag -a "$(TAG)" -m "lean v$(VERSION)"; \
	if [ -n "$$token" ]; then \
	  echo "push: $(TAG) -> github.com/voxgig/struct (HTTPS, token auth)"; \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$token" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  echo "push: $(TAG) -> origin (ssh)"; \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Published $(TAG). Lean consumers pin this tag as a lake git dependency."
