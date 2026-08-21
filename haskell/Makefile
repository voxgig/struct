# Makefile for the Haskell port of voxgig/struct.
# Requires GHC (`ghc` / `runghc`) on PATH. No third-party dependencies
# (only the GHC boot libraries: base, array, etc.).

.PHONY: test bench lint build inspect clean reset publish publish-candidate format

BUILDDIR := .hsbuild

# The corpus runner is voxgig/omni, consumed as a local checkout - it is not
# published to Hackage. $OMNI_HOME first, then sibling paths, taking the first
# directory that carries spec/fib.json.
#
# It goes on the TEST search path only: `make build` compiles src/ alone, and
# nothing shipped (the .cabal library stanza) names omni (register 4.13).
#
# $OMNI_HOME is resolved by the SHELL, not by make's `wildcard`/`foreach`.
# Those are whitespace-delimited, so a path with a space ("C:/Users/Ann
# Smith/omni") splits into two candidates that both miss - and the result is
# not an error but a silent fallthrough to the next candidate, a DIFFERENT
# checkout. `$$OMNI_HOME` reaches the shell as the raw environment value. The
# sibling candidates are fixed literals with no spaces, so they stay here.
OMNI_SIBLINGS := ../../omni ../../../omni /workspace/omni /home/user/omni
OMNI_DIR := $(or \
  $(shell [ -n "$$OMNI_HOME" ] && [ -f "$$OMNI_HOME/spec/fib.json" ] && printf '%s' "$$OMNI_HOME"),\
  $(firstword $(foreach d,$(OMNI_SIBLINGS),$(if $(wildcard $(d)/spec/fib.json),$(d)))))

.PHONY: omni-check

# Fail with the reason rather than "Could not find module `Omni'".
omni-check:
	@if [ -z "$(OMNI_DIR)" ]; then \
	  echo "struct: voxgig/omni checkout not found - set OMNI_HOME."; \
	  echo "  The tests run on the shared runner; the library itself does not."; \
	  echo "  git clone https://github.com/voxgig/omni ../../omni"; \
	  exit 1; \
	fi

# Run the shared JSON corpus through the Haskell implementation, on voxgig/omni.
test: omni-check
	@mkdir -p $(BUILDDIR)
	ghc -O0 -isrc -itest "-i$(OMNI_DIR)/haskell/src" -outputdir $(BUILDDIR) -o $(BUILDDIR)/runner test/Runner.hs
	$(BUILDDIR)/runner ../build/test/test.json

# Cross-port performance harness (JSON contract; see build/bench/README.md).
# Optimised build; compiler chatter to stderr so stdout is only the JSON line.
bench:
	@mkdir -p $(BUILDDIR)
	@ghc -O2 -isrc -ibench -outputdir $(BUILDDIR) -o $(BUILDDIR)/bench bench/Bench.hs 1>&2
	@$(BUILDDIR)/bench

# "Lint": type-check the library and runner (a clean compile = pass).
# The runner names omni, so this needs the checkout too.
lint: omni-check
	ghc -fno-code -isrc -itest "-i$(OMNI_DIR)/haskell/src" test/Runner.hs

# Compile the library as a build smoke-test.
build:
	ghc -fno-code -isrc src/VoxgigStruct.hs

format:
	@echo "haskell: (ormolu/fourmolu optional)"

inspect:
	@ghc --version

clean:
	rm -rf $(BUILDDIR) src/*.hi src/*.o test/*.hi test/*.o

reset: clean

# Release: build the source distribution and publish to Hackage (cabal upload
# --publish), then tag haskell/vX.Y.Z. NB Hackage releases are permanent (a
# version can be deprecated but never deleted). ALWAYS dry-run the real thing
# with `make publish-candidate` first: a candidate is changeable/removable, so
# use it to confirm the package page renders, the sdist builds, and Haddock is
# clean before committing to the permanent index. The .cabal version must match
# VERSION (guarded below) since the sdist tarball name comes from the .cabal.
# Auth (from the boru vault at release time, none persisted on disk):
#   HACKAGE_TOKEN  Hackage API token (hackage.haskell.org -> account -> tokens)
#   GITHUB_TOKEN   pushes the git tag
# set -e + tag-last: a failed upload never leaves a tag behind.
VERSION := $(shell cat VERSION)
TAG := haskell/v$(VERSION)
SDIST := dist-newstyle/sdist/voxgig-struct-$(VERSION).tar.gz
# (The literal keeps the legacy AQL name: it must match the boru vault's dryRunFiller constant.)
BORU_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET

# Upload a *candidate* (non-permanent, changeable, removable) so you can verify
# the package page, dependency bounds, and Haddock rendering before the one-way
# `make publish`. Lives at hackage.haskell.org/package/voxgig-struct-X.Y.Z/candidate.
# No git tag is created for a candidate. Only HACKAGE_TOKEN is needed.
publish-candidate: test
	@cabalver=$$(sed -nE 's/^version:[[:space:]]*([0-9.]+).*/\1/p' voxgig-struct.cabal); \
	  [ "$$cabalver" = "$(VERSION)" ] || { echo "version mismatch: VERSION=$(VERSION) vs .cabal=$$cabalver — bump both"; exit 1; }
	@set -e; \
	if [ "$$HACKAGE_TOKEN" = "$(BORU_DRY_RUN_FILLER)" ] || [ "$${GITHUB_TOKEN:-$$GH_TOKEN}" = "$(BORU_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] boru filler token detected: would upload candidate voxgig-struct-$(VERSION); nothing uploaded."; \
	  exit 0; \
	fi; \
	cabal sdist; \
	cabal upload --token="$$HACKAGE_TOKEN" "$(SDIST)"; \
	echo "Uploaded candidate: https://hackage.haskell.org/package/voxgig-struct-$(VERSION)/candidate"

publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump haskell/VERSION first"; exit 1; fi
	@cabalver=$$(sed -nE 's/^version:[[:space:]]*([0-9.]+).*/\1/p' voxgig-struct.cabal); \
	  [ "$$cabalver" = "$(VERSION)" ] || { echo "version mismatch: VERSION=$(VERSION) vs .cabal=$$cabalver — bump both"; exit 1; }
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(BORU_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] boru filler token detected: would publish to Hackage and tag $(TAG); nothing pushed."; \
	  exit 0; \
	fi; \
	cabal sdist; \
	cabal upload --publish --token="$$HACKAGE_TOKEN" "$(SDIST)"; \
	git tag -a "$(TAG)" -m "haskell v$(VERSION)"; \
	if [ -n "$$token" ]; then \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$token" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Published to Hackage + tag $(TAG)."
