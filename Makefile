# Top-level Makefile for all language implementations.
# Usage:
#   make test          — run tests for all languages
#   make test-zig      — run tests for one language
#   make bench         — run the performance harness (build/bench/REPORT.md)
#   make bench-go      — run the performance harness for one language
#   make lint          — run code-quality tooling (linters/formatters) for all languages
#   make lint-go       — run code-quality tooling for one language
#   make audit         — run dependency / supply-chain audits for all languages
#   make scan          — run repo-wide static analysis (secrets, SAST, deps, workflows, ...)
#   make analyze       — lint + audit + scan
#   make inspect       — show version info for all languages
#   make clean         — clean all build artifacts
#   make publish-rust  — publish ONE language to its registry + tag <lang>/vX.Y.Z
#   make publish       — show the per-language publish targets
#   make publish-all   — bump + release EVERY port (CONFIRM=yes)

# Every port directory. Target names are the dir names, used verbatim as
# `make -C <dir>`. Each port ships at least `test` and `lint`; `build`,
# `inspect`, `clean` and `reset` are invoked tolerantly (a port without one
# just reports "(no <t> target)").
LANGS = typescript javascript python go ruby php lua zig java rust c cpp csharp kotlin perl swift clojure ocaml scala dart elixir haskell lean boru

# Every port ships a `make lint` target, so lint covers the full set.
LINT_LANGS = $(LANGS)

# Languages whose ecosystem has a dependency / supply-chain audit tool wired up.
# The rest (lua zig java c cpp kotlin perl swift) ship no `audit` target, so
# they are intentionally excluded from `make audit`.
AUDIT_LANGS = typescript javascript python go ruby php rust csharp

# Every port except boru ships a `make publish` target: it publishes to that
# ecosystem's library repository where one exists (npm, PyPI, crates.io,
# NuGet, RubyGems, LuaRocks, Maven Central, CPAN) and ALWAYS creates + pushes
# a git tag `<lang>/vX.Y.Z`. Registry-less ports (Go, PHP/Packagist, Swift,
# Zig, C, C++) publish purely by that tag. The boru port has no registry and
# no tag flow yet, so it is not in PUBLISH_LANGS.
PUBLISH_LANGS = typescript javascript python go ruby php lua zig java rust c cpp csharp kotlin perl swift clojure ocaml scala dart elixir haskell lean

.PHONY: all inspect build test bench lint audit scan analyze clean reset publish publish-all status verify corpus gen-docs \
        scan-secrets scan-deps scan-sast scan-workflows scan-shell scan-spelling scan-docs \
        scan-parity scan-omni-isolation scan-regex scan-docs-examples scan-prose

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

# ---- Performance harness ----
# Build a fixed in-memory workload in each port and time the core ops
# (clone/walk/merge/stringify/getpath) in-process, then aggregate into
# build/bench/REPORT.md. Driven by tools/bench.py; see build/bench/README.md.
# `make bench` runs every wired port; `make bench-go` runs one; workload knobs
# are BENCH_RUNS / BENCH_WIDTH / BENCH_DEPTH / … (passed through the env).
bench:
	python3 tools/bench.py

bench-%:
	python3 tools/bench.py $*

# One language at a time, or all of them: `make publish-<lang>` releases one,
# `make publish-all` releases every port in PUBLISH_LANGS.
publish:
	@echo "Publishing one port at a time:"
	@echo "  make publish-<lang>   e.g.  make publish-rust"
	@echo "Languages: $(PUBLISH_LANGS)"
	@echo "Each runs the port's registry publish (where one exists) and pushes tag <lang>/vX.Y.Z."
	@echo ""
	@echo "  make publish-all CONFIRM=yes   bump + release all $(words $(PUBLISH_ALL)) ports"
	@echo "    tag-only ($(words $(PUBLISH_ALL_TAGONLY))): $(PUBLISH_ALL_TAGONLY)"
	@echo "    OIDC     ($(words $(PUBLISH_ALL_OIDC))): $(PUBLISH_ALL_OIDC)"
	@echo "    registry ($(words $(PUBLISH_ALL_REGISTRY))): $(PUBLISH_ALL_REGISTRY)"
	@echo "  A port that fails does not stop the rest; the run ends with a summary."

# ---- publish-all ----
#
# EVERY PORT IN PUBLISH_LANGS, in three groups that release differently:
#
#   PUBLISH_ALL_TAGONLY  no registry exists; the tag IS the release. Each goes
#                        through `make publish-<lang>`, so the port's own tests
#                        and its existing-tag guard still run.
#   PUBLISH_ALL_OIDC     the tag push triggers .github/workflows/publish.yml,
#                        which runs the tests again and publishes over OIDC
#                        trusted publishing. NOT `make publish-<lang>`: that
#                        path uploads over a long-lived registry token,
#                        bypassing OIDC and its provenance attestation. The two
#                        paths cut the same tag now -- typescript released
#                        under a bare `v*` until 0.3.4 and the Makefile always
#                        cut `typescript/v*`; publish.yml writes that too.
#   PUBLISH_ALL_REGISTRY an irreversible upload under that ecosystem's own
#                        credentials (PyPI, RubyGems, NuGet, CPAN, Maven,
#                        LuaRocks, Clojars, pub.dev, Hex, Hackage, opam), then
#                        its tag. These need their credentials present; a port
#                        whose credentials are missing fails and the run
#                        carries on without it.
#
# ONE PORT'S FAILURE DOES NOT STOP THE REST, and that is not a preference: the
# first real run of this target died on zig -- a local toolchain older than the
# 0.16 the port requires -- and took lean and all three OIDC ports down with
# it, none of which had anything wrong. Each port is now attempted
# independently and the run ends with a summary and a non-zero exit if any
# failed.
#
# IT IS RESUMABLE, because tools/bump.py refuses to bump past a version whose
# tag does not exist. Stop it half way -- a failed test, a rejected push, a
# missing credential -- and re-running releases the ports still outstanding at
# the versions already committed, instead of skipping them and bumping the rest
# a second time.
#
# ORDER: tag-only, then OIDC, then registry. The tag-only ports are local and
# cheap, so a broken tree shows up before anything is uploaded; the OIDC tags
# go next so their CI runs while the registry uploads proceed.
#
# THE OIDC LOOP READS A TEMP FILE, NOT A PIPE, deliberately: a piped `while`
# runs in a subshell, so every `failed=` it recorded would be discarded at the
# `done` and a failed tag push would vanish from the summary. mktemp rather
# than a file in the tree, so a run that dies mid-way leaves nothing behind for
# the next run's clean-tree guard to trip over.
#
# THE BUMP COMMIT GOES STRAIGHT TO `main`, because both halves need it there
# before anything is tagged: a tag records a commit, not a working tree, so an
# uncommitted bump tags code that still carries the old version, and
# publish.yml reads the version off the pushed branch and refuses a tag that
# does not match it. If `main` is protected against direct pushes this stops
# here, before any release -- land the bump through a PR and re-run, and the
# "nothing to bump" path picks it up.
PUBLISH_ALL_TAGONLY  = go php c cpp swift zig lean
PUBLISH_ALL_OIDC     = typescript javascript rust
PUBLISH_ALL_REGISTRY = python ruby csharp perl java kotlin scala lua clojure dart elixir haskell ocaml
PUBLISH_ALL          = $(PUBLISH_ALL_TAGONLY) $(PUBLISH_ALL_OIDC) $(PUBLISH_ALL_REGISTRY)

# `$(MAKE_BIN)`, NOT `$(MAKE)`, IN THE RECIPE BELOW. GNU make treats any recipe
# line whose text contains `$(MAKE)` as recursive and runs it even under `-n`,
# `-t` and `-q`. The recipe is one backslash-continued line, so a single
# `$(MAKE)` anywhere in it makes `make -n publish-all CONFIRM=yes` cut and push
# real release tags instead of printing what it would do -- the opposite of
# what -n is for, on the one target where that is least recoverable. Measured
# here before this indirection existed. The check is textual and pre-expansion,
# so aliasing the variable is enough to opt out of it.
MAKE_BIN := $(MAKE)

publish-all:
	@test "$(CONFIRM)" = "yes" || { \
	  echo "publish-all releases $(words $(PUBLISH_ALL)) ports and pushes their tags."; \
	  echo "Re-run as: make publish-all CONFIRM=yes"; exit 1; }
	@set -e; \
	test -z "$$(git status --porcelain)" || { echo "working tree is dirty — commit or stash first"; exit 1; }; \
	branch="$$(git rev-parse --abbrev-ref HEAD)"; \
	test "$$branch" = "main" || { echo "on $$branch — releases are cut from main"; exit 1; }; \
	git fetch --tags --quiet origin main; \
	test "$$(git rev-parse HEAD)" = "$$(git rev-parse origin/main)" || { \
	  echo "main and origin/main differ — pull or push first"; exit 1; }; \
	echo "======== bump ========"; \
	python3 tools/bump.py --ports "$$(echo $(PUBLISH_ALL) | tr ' ' ',')"; \
	if [ -n "$$(git status --porcelain)" ]; then \
	  git commit -aqm "all ports: patch bump for a release train"; \
	  git push --quiet origin main; \
	  echo "bump committed and pushed: $$(git rev-parse --short HEAD)"; \
	else \
	  echo "nothing to bump — releasing the versions already committed"; \
	fi; \
	failed=""; \
	for lang in $(PUBLISH_ALL_TAGONLY); do \
	  $(MAKE_BIN) publish-$$lang || { failed="$$failed $$lang"; \
	    echo "!! publish-$$lang FAILED — carrying on with the rest"; }; \
	done; \
	echo "======== publish: $(PUBLISH_ALL_OIDC) (tag push -> publish.yml) ========"; \
	tsv="$$(mktemp)"; \
	python3 tools/bump.py --ports "$$(echo $(PUBLISH_ALL_OIDC) | tr ' ' ',')" --plan > "$$tsv"; \
	while IFS="$$(printf '\t')" read -r lang tag version; do \
	  if git rev-parse -q --verify "refs/tags/$$tag" >/dev/null; then \
	    echo "  $$tag already exists; nothing to do"; continue; fi; \
	  if git tag -a "$$tag" -m "$$lang v$$version" && git push --quiet origin "$$tag"; then \
	    echo "  pushed $$tag — publish.yml is now releasing $$lang $$version"; \
	  else \
	    failed="$$failed $$lang"; git tag -d "$$tag" >/dev/null 2>&1 || true; \
	    echo "!! $$tag push FAILED — carrying on with the rest"; \
	  fi; \
	done < "$$tsv"; \
	rm -f "$$tsv"; \
	for lang in $(PUBLISH_ALL_REGISTRY); do \
	  $(MAKE_BIN) publish-$$lang || { failed="$$failed $$lang"; \
	    echo "!! publish-$$lang FAILED — carrying on with the rest"; }; \
	done; \
	echo ""; \
	echo "======== publish-all summary ========"; \
	if [ -n "$$failed" ]; then \
	  echo "FAILED:$$failed"; \
	  echo "Nothing else was skipped on their account — every other port was attempted."; \
	  echo "Fix them and re-run: the bump will not move a version whose tag is missing,"; \
	  echo "so a re-run releases exactly what is still outstanding."; \
	else \
	  echo "every port released"; \
	fi; \
	echo "The OIDC ports publish asynchronously:"; \
	echo "  watch   https://github.com/voxgig/struct/actions/workflows/publish.yml"; \
	echo "  verify  make status"; \
	test -z "$$failed"

# Release dashboard: per-port local version vs latest published tag vs registry.
status:
	@python3 tools/release_status.py

# Post-publish verification: install each PUBLISHED package fresh from its
# registry (or build the live tag source) and smoke-test it. Status-aware —
# only verifies ports actually published; see build/verify/.
verify:
	@$(MAKE) -C build/verify verify

# ---- Shared test corpus ----
# build/test/test.json is a COMMITTED artifact compiled from build/test/*.aon
# by @voxgig/model. Every port's test runner reads it directly. After editing any
# *.aon source (e.g. adding a doc-example entry), run `make corpus` and commit
# the regenerated test.json — CI's corpus-freshness check fails on a stale JSON.
corpus:
	@echo "======== corpus: regenerate build/test/test.json from *.aon ========"
	cd build && npm install --no-audit --no-fund --silent && npm run --silent test-model
	@echo "Regenerated build/test/test.json"

# Fill in / refresh the canonical `<!-- => json -->` output markers on every
# documentation example anchor (`<!-- example: id -->`) from the corpus. Authors
# write only the anchor; this types the hand-escaped JSON for them. CI runs the
# --check form (see scan-docs-examples) so a missing or stale marker fails the build.
gen-docs:
	@echo "======== gen: documentation example output markers from corpus ========"
	python3 tools/gen_doc_examples.py

# ---- Repo-wide static analysis (not per-language) ----
# These need their tools on PATH:
#   gitleaks, osv-scanner, semgrep, actionlint, shellcheck, cspell,
#   markdownlint, vale

scan: scan-secrets scan-deps scan-sast scan-workflows scan-shell scan-parity scan-omni-isolation scan-regex scan-docs-examples scan-spelling scan-docs scan-prose

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

# The prose gate, both halves, over the reader-facing pages. STYLE-GUIDE.md
# is what they enforce; .vale.ini records why each rule sits at its level.
#
# ONE FILE SET FOR BOTH. `check_prose.py --files` prints it, and vale is
# handed the same list rather than a directory, so a page can never be read
# by one gate and not the other.
#
# check_prose runs even when vale is not installed, because it is the half
# that carries the house rules .vale.ini switches Google rules OFF in
# favour of -- skipping it silently would widen what is allowed.
scan-prose:
	@echo "======== scan: prose (vale + check_prose) ========"
	@if command -v vale >/dev/null 2>&1; then \
	  vale sync >/dev/null && \
	  vale --minAlertLevel=error $$(python3 tools/check_prose.py --files); \
	else \
	  echo "(vale not installed - skipping the Google/banned-list half;"; \
	  echo " see .github/workflows/docs.yml for the pinned version)"; \
	fi
	@python3 tools/check_prose.py

scan-parity:
	@echo "======== scan: cross-port API parity ========"
	python3 tools/check_parity.py

scan-omni-isolation:
	@echo "======== scan: omni is declared by no shipped library (register 4.13) ========"
	python3 tools/omni_isolation.py
	@echo "-------- and the guard itself, mutation-tested --------"
	python3 tools/omni_isolation_selftest.py

scan-regex:
	@echo "======== scan: corpus regex stays inside RE2 subset ========"
	python3 tools/check_corpus_regex.py

scan-docs-examples:
	@echo "======== scan: documentation examples match the corpus ========"
	python3 tools/check_doc_examples.py
	python3 tools/gen_doc_examples.py --check

# Everything: linters/formatters + dependency audits + repo-wide scans.
analyze: lint audit scan
