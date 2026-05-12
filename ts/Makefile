.PHONY: inspect build test lint typecheck format-check clean reset

inspect:
	@echo "Node.js version:"
	@node --version
	@echo ""
	@echo "Project version:"
	@node -p "require('./package.json').version"

build:
	npm run build

test:
	npm test

# Code quality: ESLint + Prettier format check.
lint:
	npm run lint
	npm run format:check

typecheck:
	npm run typecheck

format-check:
	npm run format:check

clean:
	rm -rf dist

reset: clean
	rm -rf node_modules
