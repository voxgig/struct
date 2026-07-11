.PHONY: inspect build test lint bench walk-bench clean reset audit publish

inspect:
	@echo "PHP version:"
	@php --version | head -1
	@echo ""
	@echo "Project version:"
	@php -r "echo json_decode(file_get_contents('composer.json'))->version ?? 'unknown';" 2>/dev/null; echo ""

build:
	@echo "No build step for PHP"

test:
	vendor/bin/phpunit

# Code quality: PHP_CodeSniffer (PSR-12) + PHPStan static analysis.
lint:
	vendor/bin/phpcs
	vendor/bin/phpstan analyse --no-progress

# Cross-port performance harness (JSON contract; see build/bench/README.md).
bench:
	@php -d memory_limit=512M bench/bench.php

# Port-local walk-only micro-benchmark (human-readable).
walk-bench:
	WALK_BENCH=1 php -d memory_limit=512M tests/WalkBench.php

clean:
	@echo "Nothing to clean"

reset: clean
	rm -rf vendor

# Supply-chain: scan Composer dependencies for known vulnerabilities.
audit:
	composer audit

# Release: PHP has no upload step here — publishing IS the git tag. The package
# lives in a subdirectory, so the tag MUST be the `php/vX.Y.Z` form. Version is
# in the VERSION file.
#
# Headless publish: `aql vault exec --for=github <alias> -- make publish-php`
# injects GH_TOKEN/GITHUB_TOKEN; the tag is pushed over HTTPS via an
# Authorization header (kept out of the URL, .git/config, and argv), else the
# origin SSH remote. `aql vault exec --dry-run` injects a filler we detect to
# rehearse (no tag). set -e: a failed push never leaves a tag behind.
VERSION := $(shell cat VERSION)
TAG := php/v$(VERSION)
AQL_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump php/VERSION first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(AQL_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] aql filler token detected: would tag $(TAG) and push it over"; \
	  echo "[dry-run] HTTPS to github.com/voxgig/struct — no tag created, nothing pushed."; \
	  exit 0; \
	fi; \
	echo "tag: $(TAG)"; \
	git tag -a "$(TAG)" -m "php v$(VERSION)"; \
	if [ -n "$$token" ]; then \
	  echo "push: $(TAG) -> github.com/voxgig/struct (HTTPS, token auth)"; \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$token" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  echo "push: $(TAG) -> origin (ssh)"; \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Published $(TAG). Packagist serves voxgig/struct from this tag once the package is registered + the GitHub webhook is enabled."
