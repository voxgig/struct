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
#   make publish-rust  — publish ONE language to its registry + tag <lang>/vX.Y.Z
#   make publish       — show the per-language publish targets (no publish-all)

# Every port directory. Target names are the dir names, used verbatim as
# `make -C <dir>`. Each port ships at least `test` and `lint`; `build`,
# `inspect`, `clean` and `reset` are invoked tolerantly (a port without one
# just reports "(no <t> target)").
LANGS = typescript javascript python go ruby php lua zig java rust c cpp csharp kotlin perl swift

# Every port ships a `make lint` target, so lint covers the full set.
LINT_LANGS = $(LANGS)

# Languages whose ecosystem has a dependency / supply-chain audit tool wired up.
# The rest (lua zig java c cpp kotlin perl swift) ship no `audit` target, so
# they are intentionally excluded from `make audit`.
AUDIT_LANGS = typescript javascript python go ruby php rust csharp

# Every port ships a `make publish` target: it publishes to that ecosystem's
# library repository where one exists (npm, PyPI, crates.io, NuGet, RubyGems,
# LuaRocks, Maven Central, CPAN) and ALWAYS creates + pushes a git tag
# `<lang>/vX.Y.Z`. Registry-less ports (Go, PHP/Packagist, Swift, Zig, C, C++)
# publish purely by that tag.
PUBLISH_LANGS = typescript javascript python go ruby php lua zig java rust c cpp csharp kotlin perl swift

.PHONY: all inspect build test lint audit scan analyze clean reset publish \
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

# Publish ONE language: build/test, push to its registry (where one exists),
# and create + push the git tag <lang>/vX.Y.Z. Registry uploads expect the
# ecosystem's credentials in the environment (NPM_TOKEN, TWINE_*,
# CARGO_REGISTRY_TOKEN, NUGET_API_KEY, GEM_HOST_API_KEY, LUAROCKS_API_KEY,
# Maven settings.xml + GPG, PAUSE creds). See the port's README/DOCS.
publish-%:
	@echo "======== publish: $* ========"
	@$(MAKE) -C $* publish

# ---- Aggregate targets ----

inspect: $(LANGS:%=inspect-%)
build: $(LANGS:%=build-%)
test: $(LANGS:%=test-%)
lint: $(LINT_LANGS:%=lint-%)
audit: $(AUDIT_LANGS:%=audit-%)
clean: $(LANGS:%=clean-%)
reset: $(LANGS:%=reset-%)

# Publishing is deliberately one-language-at-a-time (each upload is
# irreversible and each cuts a version tag), so there is no publish-all.
publish:
	@echo "Publishing is per-language — pick one (each port versions independently):"
	@echo "  make publish-<lang>   e.g.  make publish-rust"
	@echo "Languages: $(PUBLISH_LANGS)"
	@echo "Each runs the port's registry publish (where one exists) and pushes tag <lang>/vX.Y.Z."

# ---- Repo-wide static analysis (not per-language) ----
# These need their tools on PATH:
#   gitleaks, osv-scanner, semgrep, actionlint, shellcheck, cspell, markdownlint

scan: scan-secrets scan-deps scan-sast scan-workflows scan-shell scan-parity scan-regex scan-spelling scan-docs

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

scan-regex:
	@echo "======== scan: corpus regex stays inside RE2 subset ========"
	python3 tools/check_corpus_regex.py

# Everything: linters/formatters + dependency audits + repo-wide scans.
analyze: lint audit scan
