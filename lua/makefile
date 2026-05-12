# Makefile - Common commands for Lua project

.PHONY: setup test lint format-check bench clean

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
