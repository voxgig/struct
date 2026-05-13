# Top-level Makefile for all language implementations.
# Usage:
#   make test          — run tests for all languages
#   make test-zig      — run tests for one language
#   make lint          — run code-quality tooling (linters/formatters) for all languages
#   make lint-go       — run code-quality tooling for one language
#   make audit         — run dependency / supply-chain audits for all languages
#   make scan          — run repo-wide static analysis (secrets, SAST, deps, workflows, ...)
#   make analyze       — lint + audit + scan
#   make inspect       — show version info for all languages
#   make clean         — clean all build artifacts

LANGS = ts js py go rb php lua zig java rs c

# Languages that ship a `make lint` target (the test/build aggregates above
# deliberately omit cpp/cs/kt, but their lint targets exist).
LINT_LANGS = ts js py go rb php lua zig java rs c cpp cs kt

# Languages whose ecosystem has a dependency / supply-chain audit tool wired up.
AUDIT_LANGS = ts js py go rb php rs cs

.PHONY: all inspect build test lint audit scan analyze clean reset \
        scan-secrets scan-deps scan-sast scan-workflows scan-shell scan-spelling scan-docs scan-parity

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

audit-%:
	@echo "======== audit: $* ========"
	@$(MAKE) -C $* audit

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
audit: $(AUDIT_LANGS:%=audit-%)
clean: $(LANGS:%=clean-%)
reset: $(LANGS:%=reset-%)

# ---- Repo-wide static analysis (not per-language) ----
# These need their tools on PATH:
#   gitleaks, osv-scanner, semgrep, actionlint, shellcheck, cspell, markdownlint

scan: scan-secrets scan-deps scan-sast scan-workflows scan-shell scan-parity scan-spelling scan-docs

scan-secrets:
	@echo "======== scan: secrets (gitleaks) ========"
	gitleaks detect --no-banner --redact --verbose

scan-deps:
	@echo "======== scan: dependencies (osv-scanner) ========"
	osv-scanner scan --config=osv-scanner.toml --recursive .

scan-sast:
	@echo "======== scan: SAST (semgrep) ========"
	semgrep scan --config p/security-audit --config p/secrets --metrics=off --error .

scan-workflows:
	@echo "======== scan: GitHub workflows (actionlint) ========"
	actionlint

scan-shell:
	@echo "======== scan: shell scripts (shellcheck) ========"
	@files=$$(git ls-files '*.sh'); \
	if [ -n "$$files" ]; then shellcheck $$files; else echo "(no shell scripts)"; fi

scan-spelling:
	@echo "======== scan: spelling (cspell) ========"
	cspell --no-progress --no-summary --gitignore "**/*.md"

scan-docs:
	@echo "======== scan: markdown (markdownlint) ========"
	markdownlint '**/*.md'

scan-parity:
	@echo "======== scan: cross-port API parity ========"
	python3 tools/check_parity.py

# Everything: linters/formatters + dependency audits + repo-wide scans.
analyze: lint audit scan
