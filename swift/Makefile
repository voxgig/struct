.PHONY: inspect build test lint clean reset

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
