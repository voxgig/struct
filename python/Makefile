.PHONY: inspect build test lint format-check typecheck bench walk-bench walk-bench-quick clean reset audit publish

inspect:
	@echo "Python version:"
	@python3 --version
	@echo ""
	@echo "Project version:"
	@python3 -c "import voxgig_struct; print(getattr(voxgig_struct, '__version__', 'unknown'))" 2>/dev/null || echo "unknown"

build:
	@echo "No build step for Python"

test:
	python3 -m unittest discover -s tests

# Code quality: Ruff (lint), Ruff (format check), mypy (static types).
lint:
	ruff check voxgig_struct tests
	ruff format --check voxgig_struct tests
	mypy

format-check:
	ruff format --check voxgig_struct tests

typecheck:
	mypy

# Cross-port performance harness (JSON contract; see build/bench/README.md).
bench:
	@python3 bench/bench.py

# Port-local walk-only micro-benchmark (human-readable).
walk-bench:
	WALK_BENCH=1 python3 -m unittest discover -s tests -p 'test_walk_bench.py' -v

walk-bench-quick:
	WALK_BENCH=1 \
	  WALK_BENCH_VD_DEPTH=16 WALK_BENCH_RUNS_VD=3 WALK_BENCH_WARMUP=1 \
	  WALK_BENCH_RUNS_WD=5 WALK_BENCH_RUNS_VW=5 \
	  python3 -m unittest discover -s tests -p 'test_walk_bench.py' -v

clean:
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	rm -rf *.egg-info dist build

reset: clean

# Supply-chain + security: dependency vuln scan (pip-audit) + Bandit SAST.
audit:
	pip-audit -r requirements-dev.txt
	bandit -q -r voxgig_struct

# Release: build sdist+wheel, upload to PyPI, then tag python/vX.Y.Z (version from pyproject.toml).
#
# Toolchain: the publish path uses `uv` (build + publish + the project's
# pinned Python from requires-python), so it does NOT depend on the system
# python3 (macOS ships 3.9, too old). The shared `test` target stays on plain
# python3 for CI (actions/setup-python); here we re-run the tests via
# `uv run` so a local publish is fully uv-driven.
#
# PyPI auth: `uv publish` reads UV_PUBLISH_TOKEN, which a headless run
# supplies with `aql vault exec --for=uv <alias> -- make publish-python`. The
# git tag push needs GitHub auth: with GH_TOKEN/GITHUB_TOKEN present we push
# over HTTPS via an Authorization header (kept out of the URL, .git/config,
# and argv); otherwise we fall back to the origin SSH remote.
#
# Dry-run cooperation: `aql vault exec --dry-run` injects a fixed filler in
# place of the real token; when the PyPI or GitHub token is that filler we
# build + `uv publish --dry-run` (validating packaging), then stop — nothing
# uploaded, no tag.
VERSION := $(shell grep -E '^version[[:space:]]*=' pyproject.toml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
TAG := python/v$(VERSION)
AQL_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish:
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump pyproject.toml version first"; exit 1; fi
	uv run python -m unittest discover -s tests
	uv build
	@set -e; \
	pypitok="$$UV_PUBLISH_TOKEN"; ghtok="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$pypitok" = "$(AQL_DRY_RUN_FILLER)" ] || [ "$$ghtok" = "$(AQL_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] aql filler token detected: uv publish --dry-run; nothing uploaded, no $(TAG) tag."; \
	  uv publish --dry-run; \
	  exit 0; \
	fi; \
	uv publish; \
	echo "tag: $(TAG)"; \
	git tag -a "$(TAG)" -m "python v$(VERSION)"; \
	if [ -n "$$ghtok" ]; then \
	  echo "push: $(TAG) -> github.com/voxgig/struct (HTTPS, token auth)"; \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$ghtok" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  echo "push: $(TAG) -> origin (ssh)"; \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Published voxgig-struct $(VERSION) + tag $(TAG)."
