# Makefile for the Haskell port of voxgig/struct.
# Requires GHC (`ghc` / `runghc`) on PATH. No third-party dependencies
# (only the GHC boot libraries: base, array, etc.).

.PHONY: test lint build inspect clean reset publish format

BUILDDIR := .hsbuild

# Run the shared JSON corpus through the Haskell implementation.
test:
	@mkdir -p $(BUILDDIR)
	ghc -O0 -isrc -itest -outputdir $(BUILDDIR) -o $(BUILDDIR)/runner test/Runner.hs
	$(BUILDDIR)/runner ../build/test/test.json

# "Lint": type-check the library and runner (a clean compile = pass).
lint:
	ghc -fno-code -isrc -itest test/Runner.hs

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

# Release: Hackage registry upload is a documented manual step for now; this
# target cuts the haskell/vX.Y.Z git tag headlessly.
# Headless: `aql vault exec --for=github <alias> -- make publish-haskell` injects
# GH_TOKEN/GITHUB_TOKEN; the tag is pushed over HTTPS via an Authorization header
# (kept out of the URL, .git/config, and argv), else the origin SSH remote.
# `aql vault exec --dry-run` injects a filler we detect to rehearse (no tag).
# set -e: a failed push never leaves a tag behind.
VERSION := $(shell cat VERSION)
TAG := haskell/v$(VERSION)
AQL_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump haskell/VERSION first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(AQL_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] aql filler token detected: would tag $(TAG) and push it over"; \
	  echo "[dry-run] HTTPS to github.com/voxgig/struct — no tag created, nothing pushed."; \
	  exit 0; \
	fi; \
	echo "tag: $(TAG)"; \
	git tag -a "$(TAG)" -m "haskell v$(VERSION)"; \
	if [ -n "$$token" ]; then \
	  echo "push: $(TAG) -> github.com/voxgig/struct (HTTPS, token auth)"; \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$token" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  echo "push: $(TAG) -> origin (ssh)"; \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Tagged $(TAG). Hackage upload (manual): cabal upload"
