.PHONY: inspect build test bench lint clean reset publish omni-check

SWIFT ?= swift

# The corpus runner is voxgig/omni, consumed as a local checkout - it is not
# published. $OMNI_HOME first, then sibling paths, taking the first directory
# that carries spec/fib.json.
#
# It reaches SwiftPM through `.omni-runner`, a gitignored symlink this target
# points at omni's package directory: SwiftPM takes a path dependency's
# identity from the last path component, and omni's package is at `omni/swift`
# - the same basename as this one, which it reads as a self-dependency. The
# symlink gives it a distinct identity. Package.swift declares the dependency
# only when the symlink is there, so `make build` compiles the library alone
# (register 4.13).
OMNI_CANDIDATES := $(OMNI_HOME) ../../omni ../../../omni /workspace/omni /home/user/omni
OMNI_DIR := $(firstword $(foreach d,$(OMNI_CANDIDATES),$(if $(wildcard $(d)/spec/fib.json),$(d))))

omni-check:
	@if [ -z "$(OMNI_DIR)" ]; then \
	  echo "struct: voxgig/omni checkout not found - set OMNI_HOME."; \
	  echo "  The tests run on the shared runner; the library itself does not."; \
	  echo "  git clone https://github.com/voxgig/omni ../../omni"; \
	  exit 1; \
	fi
	@ln -sfn "$$(cd $(OMNI_DIR)/swift && pwd)" .omni-runner

inspect:
	@echo "Swift version:"
	@$(SWIFT) --version
	@echo ""
	@echo "Package:"
	@$(SWIFT) package describe --type text 2>/dev/null | head -6

build:
	$(SWIFT) build

test: omni-check
	$(SWIFT) test

# Cross-port performance harness (JSON contract; see build/bench/README.md).
# Release build (SwiftPM logs to stderr; stdout carries only the JSON line).
bench:
	@BENCH_SWIFT="$$($(SWIFT) --version 2>/dev/null | head -1 | cut -c1-24)" \
	  $(SWIFT) run -c release bench

# `swift format` is bundled with the Swift toolchain (`swift-format`).
# Local soft-skip when not on PATH; CI hardens this by setting CI=true
# so a missing tool is a hard failure.
lint:
	@if command -v swift-format >/dev/null 2>&1; then \
		swift-format lint --strict --recursive Sources Tests; \
	elif [ "$$CI" = "true" ]; then \
		echo "swift-format not installed (required in CI)"; exit 1; \
	else \
		echo "swift-format not installed — skipping lint"; \
	fi

clean:
	$(SWIFT) package clean
	rm -rf .build

reset: clean
	rm -rf Package.resolved

# Release: SwiftPM has no upload step — publishing IS the git tag. The package
# lives in a subdirectory, so the tag MUST be the `swift/vX.Y.Z` form. Version
# is in the VERSION file.
#
# Headless publish: `boru vault exec --for=github <alias> -- make publish-swift`
# injects GH_TOKEN/GITHUB_TOKEN; the tag is pushed over HTTPS via an
# Authorization header (kept out of the URL, .git/config, and argv), else the
# origin SSH remote. `boru vault exec --dry-run` injects a filler we detect to
# rehearse (no tag). set -e: a failed push never leaves a tag behind.
VERSION := $(shell cat VERSION)
TAG := swift/v$(VERSION)
# (The literal keeps the legacy AQL name: it must match the boru vault's dryRunFiller constant.)
BORU_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump swift/VERSION first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(BORU_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] boru filler token detected: would tag $(TAG) and push it over"; \
	  echo "[dry-run] HTTPS to github.com/voxgig/struct — no tag created, nothing pushed."; \
	  exit 0; \
	fi; \
	echo "tag: $(TAG)"; \
	git tag -a "$(TAG)" -m "swift v$(VERSION)"; \
	if [ -n "$$token" ]; then \
	  echo "push: $(TAG) -> github.com/voxgig/struct (HTTPS, token auth)"; \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$token" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  echo "push: $(TAG) -> origin (ssh)"; \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Published $(TAG). SwiftPM resolves by git tag."
