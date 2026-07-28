# Makefile for the Lean 4 port of voxgig/struct.
# Requires the Lean toolchain (elan provides `lake`/`lean`; the version is
# pinned by ./lean-toolchain). No third-party libraries.

# elan installs to ~/.elan/bin; prepend it so a stock elan install just works.
export PATH := $(HOME)/.elan/bin:$(PATH)

.PHONY: test bench lint build inspect clean reset publish

# Build and run the shared JSON corpus through the Lean implementation.
test: build
	./.lake/build/bin/runner ../build/test/test.json

build:
	lake build

# "Lint": type-check the library (a clean compile means it is sound; the
# build is warnings-clean). No third-party linter exists for Lean.
lint: build
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
AQL_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump lean/VERSION first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(AQL_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] aql filler token detected: would tag $(TAG) and push it over"; \
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
