# Makefile - Common commands for Lua project

.PHONY: setup test bench clean

# Setup the environment
setup:
	chmod +x setup.sh
	./setup.sh

# Run tests
test:
	PATH="$(HOME)/.luarocks/bin:$$PATH" find ./test/ -name "*test.lua" | xargs $$(command -v busted || echo $(HOME)/.luarocks/bin/busted)

# Run walk() benchmark. Gated on WALK_BENCH=1 inside the script.
bench:
	WALK_BENCH=1 lua test/walk_bench.lua

# Clean artifacts
clean:
	rm -rf luacov.* .busted
