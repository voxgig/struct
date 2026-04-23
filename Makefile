# Top-level Makefile for all language implementations.
# Usage:
#   make test          — run tests for all languages
#   make test-zig      — run tests for one language
#   make inspect       — show version info for all languages
#   make clean         — clean all build artifacts

LANGS = ts js py go rb php lua zig java

.PHONY: all inspect build test clean reset

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
clean: $(LANGS:%=clean-%)
reset: $(LANGS:%=reset-%)
