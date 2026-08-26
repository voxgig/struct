# Makefile for the Lean 4 port of voxgig/struct.
# Requires the Lean toolchain (elan provides `lake`/`lean`; the version is
# pinned by ./lean-toolchain). No third-party libraries.

# elan installs to ~/.elan/bin; prepend it so a stock elan install just works.
export PATH := $(HOME)/.elan/bin:$(PATH)

.PHONY: test bench lint build inspect clean reset publish omni-fetch

# The corpus runner is voxgig/omni, taken from its release tag: this fetches
# `lean/Omni.lean` at `lean/v0.1.0` and copies it into `.omni-build`, which
# lakefile.toml declares as a lean_lib that only the RUNNER imports.
#
# COPIED, not required, and that is deliberate. Lake has no test-scoped
# dependency: a `[[require]]` is resolved by everyone who requires THIS
# package, so declaring omni there would put the test runner into every
# consumer's dependency graph - register 4.13, and the one thing this port
# must not do. Fetching the tag here instead keeps the pin and the isolation
# at once, which a `[[require]]` cannot.
OMNI_URL := https://github.com/voxgig/omni
OMNI_TAG := lean/v0.1.0
# The commit that tag must resolve to. A tag can be moved, and this repo has
# pinned a release, not a name: if the two disagree the build stops rather
# than silently testing against a different omni.
OMNI_SHA := a710fcda81b0a72a5e98322cac0af56ab8c2d959

# $OMNI_HOME overrides the fetch, for working against an omni that is not
# released yet. Unset - the normal case - the tag is what is used, and
# `.omni-build/.source` records which, so a second run needs no network.
omni-fetch:
	@if [ -n "$$OMNI_HOME" ] && [ -f "$$OMNI_HOME/lean/Omni.lean" ]; then \
	  mkdir -p .omni-build; \
	  cp "$$OMNI_HOME/lean/Omni.lean" .omni-build/Omni.lean; \
	  printf 'OMNI_HOME %s\n' "$$OMNI_HOME" > .omni-build/.source; \
	  echo "omni: $$OMNI_HOME (OMNI_HOME override)"; \
	  exit 0; \
	fi; \
	if [ "$$(cat .omni-build/.source 2>/dev/null)" = "$(OMNI_TAG) $(OMNI_SHA)" ]; then exit 0; fi; \
	rm -rf .omni-src; \
	mkdir -p .omni-build; \
	git -c advice.detachedHead=false clone --quiet --depth 1 \
	  --branch "$(OMNI_TAG)" "$(OMNI_URL)" .omni-src || \
	  { echo "struct: could not fetch $(OMNI_TAG) from $(OMNI_URL)"; exit 1; }; \
	got=$$(git -C .omni-src rev-parse HEAD); \
	if [ "$$got" != "$(OMNI_SHA)" ]; then \
	  echo "struct: $(OMNI_TAG) resolves to $$got, not the pinned $(OMNI_SHA)."; \
	  echo "  The tag moved. Refusing to build against an omni this repo has not pinned."; \
	  rm -rf .omni-src; exit 1; \
	fi; \
	cp .omni-src/lean/Omni.lean .omni-build/Omni.lean; \
	rm -rf .omni-src; \
	printf '%s %s\n' "$(OMNI_TAG)" "$(OMNI_SHA)" > .omni-build/.source; \
	echo "omni: $(OMNI_TAG) ($(OMNI_SHA))"

# Build and run the shared JSON corpus through the Lean implementation, on
# voxgig/omni.
test: omni-fetch
	lake build runner
	./.lake/build/bin/runner ../build/test/test.json

# The LIBRARY alone: nothing shipped names omni (register 4.13).
build:
	lake build VoxgigStruct

# "Lint": type-check the library (a clean compile means it is sound). No
# third-party linter exists for Lean. The runner imports omni, so this needs
# it fetched too - and omni's Omni.lean supports Lean 4.16 as well as the
# 4.32 pinned here, so it carries deprecation warnings for names that do not
# exist in 4.16 yet. Those are omni's; this port's own build is warnings-clean.
lint: omni-fetch
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
