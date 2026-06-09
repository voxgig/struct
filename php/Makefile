.PHONY: inspect build test lint clean reset audit publish

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

bench:
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
VERSION := $(shell cat VERSION)
publish: test
	@if git rev-parse -q --verify "refs/tags/php/v$(VERSION)" >/dev/null; then \
	  echo "tag php/v$(VERSION) already exists — bump php/VERSION first"; exit 1; fi
	git tag -a "php/v$(VERSION)" -m "php v$(VERSION)"
	git push origin "php/v$(VERSION)"
	@echo "Published php/v$(VERSION). Packagist serves voxgig/struct from this tag once the package is registered + the GitHub webhook is enabled."
