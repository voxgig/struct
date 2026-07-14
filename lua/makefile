# Makefile - Common commands for Lua project

.PHONY: setup test lint format-check bench walk-bench clean publish

# Setup the environment
setup:
	chmod +x setup.sh
	./setup.sh

# Run tests
test:
	PATH="$(HOME)/.luarocks/bin:$$PATH" find ./test/ -name "*test.lua" | xargs $$(command -v busted || echo $(HOME)/.luarocks/bin/busted)

# Code quality: luacheck (lint) + StyLua (format check).
# Install with:  luarocks install luacheck
#                cargo install stylua --features lua54   (5.3+ bitwise ops)
lint:
	luacheck src test
	stylua --check src test

format-check:
	stylua --check src test

# Cross-port performance harness (JSON contract; see build/bench/README.md).
LUA ?= lua5.4
bench:
	@$(LUA) bench/bench.lua

# Port-local walk-only micro-benchmark (human-readable).
walk-bench:
	WALK_BENCH=1 lua test/walk_bench.lua

# Clean artifacts
clean:
	rm -rf luacov.* .busted

# Release: publish to LuaRocks, then tag lua/vX.Y.Z (version from the rockspec,
# stripping the rockspec revision suffix). Needs LuaRocks auth (LUAROCKS_API_KEY).
# LuaRocks requires the rockspec *filename* to be name-version-revision, so we
# upload a canonically-named copy of the in-tree struct.rockspec.
#
# `--skip-pack`: upload the rockspec ONLY, never a packed .src.rock. Packing
# would fetch the source at `source.tag = lua/vX.Y.Z` — but that tag is pushed
# in the LAST step (kept last so a failed upload never orphans a tag). Install
# fetches the git source at the tag, which exists by then. So we must not pack.
VERSION := $(shell grep -E '^version' struct.rockspec | sed -E 's/.*"([0-9.]+)-[0-9]+".*/\1/')
ROCKREV := $(shell grep -E '^version' struct.rockspec | sed -E 's/.*"([0-9.]+-[0-9]+)".*/\1/')
TAG := lua/v$(VERSION)
AQL_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump struct.rockspec first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(AQL_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] aql filler token detected: would publish rock and tag $(TAG); nothing pushed."; \
	  exit 0; \
	fi; \
	cp struct.rockspec "voxgig-struct-$(ROCKREV).rockspec"; \
	luarocks upload --skip-pack "voxgig-struct-$(ROCKREV).rockspec" --api-key=$$LUAROCKS_API_KEY; \
	rm -f "voxgig-struct-$(ROCKREV).rockspec"; \
	git tag -a "$(TAG)" -m "lua v$(VERSION)"; \
	if [ -n "$$token" ]; then \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$token" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Published rock + tag $(TAG)."
