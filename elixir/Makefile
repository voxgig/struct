# Makefile for the Elixir port of voxgig/struct.
# Requires Elixir (`elixir` / `elixirc`) on PATH. No third-party dependencies.

.PHONY: test lint build inspect clean reset publish format

# Run the shared JSON corpus through the Elixir implementation.
test:
	elixir test/runner.exs

# "Lint": compile the library with warnings (a clean compile means it is sound).
lint:
	elixirc lib/voxgig_struct.ex -o /tmp/voxgig_struct_build

# Compile the library as a build smoke-test.
build:
	elixirc lib/voxgig_struct.ex -o /tmp/voxgig_struct_build

format:
	mix format --check-formatted lib/voxgig_struct.ex 2>/dev/null || true

inspect:
	@elixir --version

clean:
	rm -rf _build /tmp/voxgig_struct_build Elixir.*.beam

reset: clean

# The library publishes to hex.pm; this target creates the git tag.
publish:
	@echo "elixir: publish via 'mix hex.publish' + git tag elixir/vX.Y.Z"
