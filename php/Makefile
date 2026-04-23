.PHONY: inspect build test bench clean reset

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

bench:
	WALK_BENCH=1 php -d memory_limit=512M tests/WalkBench.php

clean:
	@echo "Nothing to clean"

reset: clean
	rm -rf vendor
