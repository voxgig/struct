# Makefile - Common commands for Lua project

.PHONY: setup test lint format-check bench clean publish

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

# Run walk() benchmark. Gated on WALK_BENCH=1 inside the script.
bench:
	WALK_BENCH=1 lua test/walk_bench.lua

# Clean artifacts
clean:
	rm -rf luacov.* .busted

# Release: publish to LuaRocks, then tag lua/vX.Y.Z (version from the rockspec,
# stripping the rockspec revision suffix). Needs LuaRocks auth (LUAROCKS_API_KEY).
# LuaRocks requires the rockspec *filename* to be name-version-revision, so we
# upload a canonically-named copy of the in-tree struct.rockspec.
VERSION := $(shell grep -E '^version' struct.rockspec | sed -E 's/.*"([0-9.]+)-[0-9]+".*/\1/')
ROCKREV := $(shell grep -E '^version' struct.rockspec | sed -E 's/.*"([0-9.]+-[0-9]+)".*/\1/')
publish: test
	cp struct.rockspec "voxgig-struct-$(ROCKREV).rockspec"
	luarocks upload "voxgig-struct-$(ROCKREV).rockspec" --api-key=$$LUAROCKS_API_KEY
	rm -f "voxgig-struct-$(ROCKREV).rockspec"
	@if git rev-parse -q --verify "refs/tags/lua/v$(VERSION)" >/dev/null; then \
	  echo "tag lua/v$(VERSION) already exists — bump struct.rockspec version first"; exit 1; fi
	git tag -a "lua/v$(VERSION)" -m "lua v$(VERSION)"
	git push origin "lua/v$(VERSION)"
