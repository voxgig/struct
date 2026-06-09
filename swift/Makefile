.PHONY: inspect build test lint clean reset publish

SWIFT ?= swift

inspect:
	@echo "Swift version:"
	@$(SWIFT) --version
	@echo ""
	@echo "Package:"
	@$(SWIFT) package describe --type text 2>/dev/null | head -6

build:
	$(SWIFT) build

test:
	$(SWIFT) test --enable-test-discovery

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
VERSION := $(shell cat VERSION)
publish: test
	@if git rev-parse -q --verify "refs/tags/swift/v$(VERSION)" >/dev/null; then \
	  echo "tag swift/v$(VERSION) already exists — bump swift/VERSION first"; exit 1; fi
	git tag -a "swift/v$(VERSION)" -m "swift v$(VERSION)"
	git push origin "swift/v$(VERSION)"
	@echo "Published swift/v$(VERSION). SwiftPM resolves by git tag."
