.PHONY: inspect build test lint fmt-check clean reset publish

# zig 0.13 cannot link against very new Xcode SDKs on macOS (e.g. the Xcode 26
# SDK): every libc symbol (_malloc, _sigaction, __availability_version_check…)
# comes back undefined. The Command Line Tools SDK still works, so point zig at
# it when CLT is installed and the caller hasn't set their own DEVELOPER_DIR.
# macOS-only and a no-op where CLT is absent (Linux CI, minimal runners).
ifeq ($(shell uname),Darwin)
ifndef DEVELOPER_DIR
ifneq ($(wildcard /Library/Developer/CommandLineTools/.),)
export DEVELOPER_DIR := /Library/Developer/CommandLineTools
endif
endif
endif

# Inspect: show language and project version info
inspect:
	@echo "Zig version:"
	@zig version
	@echo ""
	@echo "Project version:"
	@grep '.version' build.zig.zon | head -1 | sed 's/.*"\(.*\)".*/\1/'

# Build the library
build:
	zig build

# Code quality: `zig fmt` formatting check. The compiler itself (zig build)
# is the static analyser for Zig; there is no separate community linter.
lint: fmt-check

fmt-check:
	zig fmt --check src test build.zig

# Run all tests.
# The zig test framework sometimes crashes with signal 11 during cleanup
# after all tests pass, due to *MapRef/*ListRef cross-references in arena
# teardown. We filter the output: if "N/N tests passed" with N==total, success.
# `--summary all` is required: without it, plain `zig build test` prints
# `test success` with no count and the N/N grep below never matches.
test:
	@out=$$(zig build test --summary all 2>&1 || true); \
	echo "$$out"; \
	passed=$$(echo "$$out" | grep -oE '[0-9]+/[0-9]+ tests passed' | head -1); \
	if [ -n "$$passed" ]; then \
		x=$$(echo "$$passed" | cut -d/ -f1); \
		y=$$(echo "$$passed" | cut -d/ -f2 | cut -d' ' -f1); \
		if [ "$$x" = "$$y" ] && [ "$$x" -gt 0 ]; then \
			exit 0; \
		fi; \
	fi; \
	exit 1

# Clean build artifacts
clean:
	rm -rf .zig-cache zig-out

# Full reset: clean + remove fetched dependencies
reset: clean
	rm -rf .zig-cache

# Release: Zig has no registry — publishing IS the git tag. The port lives in a
# subdirectory, so the tag MUST be the `zig/vX.Y.Z` form. Version is read from
# the build.zig.zon manifest (Zig's package version field).
VERSION := $(shell grep -E '\.version' build.zig.zon | sed -E 's/.*"([^"]+)".*/\1/')
publish: test
	@if git rev-parse -q --verify "refs/tags/zig/v$(VERSION)" >/dev/null; then \
	  echo "tag zig/v$(VERSION) already exists — bump .version in build.zig.zon first"; exit 1; fi
	git tag -a "zig/v$(VERSION)" -m "zig v$(VERSION)"
	git push origin "zig/v$(VERSION)"
	@echo "Published zig/v$(VERSION). Zig consumers fetch this tag via build.zig.zon (URL + hash)."
