.PHONY: inspect build test lint typecheck format-check clean reset audit publish

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

# Supply-chain: scan dependencies for known vulnerabilities.
audit:
	npm audit --audit-level=high

# Release: publish to npm, then tag typescript/vX.Y.Z (version from package.json).
# Needs npm auth (NPM_TOKEN / `npm login`). Dry-run the package with:
#   npm publish --dry-run
VERSION := $(shell node -p "require('./package.json').version" 2>/dev/null)
publish: build test
	npm publish --access public --registry https://registry.npmjs.org
	@if git rev-parse -q --verify "refs/tags/typescript/v$(VERSION)" >/dev/null; then \
	  echo "tag typescript/v$(VERSION) already exists — bump package.json version first"; exit 1; fi
	git tag -a "typescript/v$(VERSION)" -m "typescript v$(VERSION)"
	git push origin "typescript/v$(VERSION)"
