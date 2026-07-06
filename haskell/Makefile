# Makefile for the Haskell port of voxgig/struct.
# Requires GHC (`ghc` / `runghc`) on PATH. No third-party dependencies
# (only the GHC boot libraries: base, array, etc.).

.PHONY: test lint build inspect clean reset publish publish-candidate format

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

# Release: build the source distribution and publish to Hackage (cabal upload
# --publish), then tag haskell/vX.Y.Z. NB Hackage releases are permanent (a
# version can be deprecated but never deleted). The .cabal version must match
# VERSION (guarded below) since the sdist tarball name comes from the .cabal.
# Auth (from the aql vault at release time, none persisted on disk):
#   HACKAGE_TOKEN  Hackage API token (hackage.haskell.org -> account -> tokens)
#   GITHUB_TOKEN   pushes the git tag
# set -e + tag-last: a failed upload never leaves a tag behind.
VERSION := $(shell cat VERSION)
TAG := haskell/v$(VERSION)
SDIST := dist-newstyle/sdist/voxgig-struct-$(VERSION).tar.gz
AQL_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump haskell/VERSION first"; exit 1; fi
	@cabalver=$$(sed -nE 's/^version:[[:space:]]*([0-9.]+).*/\1/p' voxgig-struct.cabal); \
	  [ "$$cabalver" = "$(VERSION)" ] || { echo "version mismatch: VERSION=$(VERSION) vs .cabal=$$cabalver — bump both"; exit 1; }
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(AQL_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] aql filler token detected: would publish to Hackage and tag $(TAG); nothing pushed."; \
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

# Live-registry rehearsal: upload a *candidate* to Hackage (same real auth and
# tarball as `publish`, but WITHOUT `--publish`, so it lands in the package's
# candidates area instead of cutting a permanent release). Nothing is tagged or
# pushed to git. Review/test-install it at the candidate URL below, then either
# publish for real (`make publish`) or delete the candidate on Hackage. Only the
# Hackage token is needed (no git tag => no GitHub token). Dry-run: aql injects
# the filler as HACKAGE_TOKEN and this makes NO upload.
CANDURL := https://hackage.haskell.org/package/voxgig-struct-$(VERSION)/candidate
publish-candidate: test
	@cabalver=$$(sed -nE 's/^version:[[:space:]]*([0-9.]+).*/\1/p' voxgig-struct.cabal); \
	  [ "$$cabalver" = "$(VERSION)" ] || { echo "version mismatch: VERSION=$(VERSION) vs .cabal=$$cabalver — bump both"; exit 1; }
	@set -e; \
	if [ "$$HACKAGE_TOKEN" = "$(AQL_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] aql filler token detected: would upload candidate voxgig-struct-$(VERSION) to Hackage; nothing uploaded."; \
	  exit 0; \
	fi; \
	cabal sdist; \
	cabal upload --token="$$HACKAGE_TOKEN" "$(SDIST)"; \
	echo "Uploaded candidate. Review at $(CANDURL)"
