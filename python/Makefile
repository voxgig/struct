.PHONY: inspect build test lint format-check typecheck bench clean reset audit publish

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

bench:
	WALK_BENCH=1 python3 -m unittest discover -s tests -p 'test_walk_bench.py' -v

bench-quick:
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
# Needs PyPI auth (TWINE_USERNAME/TWINE_PASSWORD or ~/.pypirc). Check the package locally with:
#   python3 -m build && twine check dist/*
VERSION := $(shell python3 -c "import tomllib;print(tomllib.load(open('pyproject.toml','rb'))['project']['version'])" 2>/dev/null)
publish: test
	python3 -m build
	twine upload dist/*
	@if git rev-parse -q --verify "refs/tags/python/v$(VERSION)" >/dev/null; then \
	  echo "tag python/v$(VERSION) already exists — bump pyproject.toml version first"; exit 1; fi
	git tag -a "python/v$(VERSION)" -m "python v$(VERSION)"
	git push origin "python/v$(VERSION)"
