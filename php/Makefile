.PHONY: inspect build test lint clean reset audit

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
