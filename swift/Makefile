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

# `swift format` is bundled with the toolchain (`swift-format`); if it
# isn't on PATH, lint is a no-op rather than a hard failure.
lint:
	@if command -v swift-format >/dev/null 2>&1; then \
		swift-format lint --recursive Sources Tests; \
	else \
		echo "swift-format not installed — skipping lint"; \
	fi

clean:
	$(SWIFT) package clean
	rm -rf .build

reset: clean
	rm -rf Package.resolved
