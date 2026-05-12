# Top-level Makefile for all language implementations.
# Usage:
#   make test          — run tests for all languages
#   make test-zig      — run tests for one language
#   make lint          — run code-quality tooling for all languages
#   make lint-go       — run code-quality tooling for one language
#   make inspect       — show version info for all languages
#   make clean         — clean all build artifacts

LANGS = ts js py go rb php lua zig java rs

# Languages that ship a `make lint` target (the test/build aggregates above
# deliberately omit cpp/cs/kt, but their lint targets exist).
LINT_LANGS = ts js py go rb php lua zig java rs cpp cs kt

.PHONY: all inspect build test lint clean reset

all: test

# ---- Per-language targets ----

inspect-%:
	@echo "======== $* ========"
	@$(MAKE) -C $* inspect 2>/dev/null || echo "(no inspect target)"
	@echo ""

build-%:
	@echo "======== $* ========"
	@$(MAKE) -C $* build 2>/dev/null || echo "(no build target)"

test-%:
	@echo "======== $* ========"
	@$(MAKE) -C $* test

lint-%:
	@echo "======== lint: $* ========"
	@$(MAKE) -C $* lint

clean-%:
	@echo "======== $* ========"
	@$(MAKE) -C $* clean 2>/dev/null || echo "(no clean target)"

reset-%:
	@echo "======== $* ========"
	@$(MAKE) -C $* reset 2>/dev/null || echo "(no reset target)"

# ---- Aggregate targets ----

inspect: $(LANGS:%=inspect-%)
build: $(LANGS:%=build-%)
test: $(LANGS:%=test-%)
lint: $(LINT_LANGS:%=lint-%)
clean: $(LANGS:%=clean-%)
reset: $(LANGS:%=reset-%)
