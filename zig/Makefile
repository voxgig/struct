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
#
# Headless publish: `aql vault exec --for=github <alias> -- make publish-zig`
# injects GH_TOKEN/GITHUB_TOKEN; the tag is pushed over HTTPS via an
# Authorization header (kept out of the URL, .git/config, and argv), else the
# origin SSH remote. `aql vault exec --dry-run` injects a filler we detect to
# rehearse (no tag). set -e: a failed push never leaves a tag behind.
VERSION := $(shell grep -E '\.version' build.zig.zon | sed -E 's/.*"([^"]+)".*/\1/')
TAG := zig/v$(VERSION)
AQL_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump .version in build.zig.zon first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(AQL_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] aql filler token detected: would tag $(TAG) and push it over"; \
	  echo "[dry-run] HTTPS to github.com/voxgig/struct — no tag created, nothing pushed."; \
	  exit 0; \
	fi; \
	echo "tag: $(TAG)"; \
	git tag -a "$(TAG)" -m "zig v$(VERSION)"; \
	if [ -n "$$token" ]; then \
	  echo "push: $(TAG) -> github.com/voxgig/struct (HTTPS, token auth)"; \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$token" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  echo "push: $(TAG) -> origin (ssh)"; \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Published $(TAG). Zig consumers fetch this tag via build.zig.zon (URL + hash)."
