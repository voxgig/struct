.PHONY: inspect build test lint format-check clean reset audit publish

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

# Release: publish to npm, then tag javascript/vX.Y.Z (version from package.json).
# JS has no build step, so this depends on test only.
# Needs npm auth (NPM_TOKEN / `npm login`). Dry-run the package with:
#   npm publish --dry-run
VERSION := $(shell node -p "require('./package.json').version" 2>/dev/null)
publish: test
	npm publish --access public --registry https://registry.npmjs.org
	@if git rev-parse -q --verify "refs/tags/javascript/v$(VERSION)" >/dev/null; then \
	  echo "tag javascript/v$(VERSION) already exists — bump package.json version first"; exit 1; fi
	git tag -a "javascript/v$(VERSION)" -m "javascript v$(VERSION)"
	git push origin "javascript/v$(VERSION)"
