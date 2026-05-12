.PHONY: inspect build test lint format-check clean reset audit

inspect:
	@echo "Node.js version:"
	@node --version
	@echo ""
	@echo "Project version:"
	@node -p "require('./package.json').version"

build:
	@echo "No build step for JS"

test:
	npm test

# Code quality: ESLint + Prettier format check.
lint:
	npm run lint
	npm run format:check

format-check:
	npm run format:check

clean:
	@echo "Nothing to clean"

reset: clean
	rm -rf node_modules

# Supply-chain: scan dependencies for known vulnerabilities.
audit:
	npm audit --audit-level=high
