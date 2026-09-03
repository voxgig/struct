.PHONY: inspect build test omni-check bench lint typecheck format-check clean reset audit publish

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

# REGISTER 4.13: omni is a TEST dependency and nothing shipped may reach
# it. Run AFTER `make build` - one of the four checks reads what npm pack
# would send, which comes off disk.
omni-check: build
	@node tools/omni-isolation.js

# Performance bench: build the library (src project only; the test project
# needs @types/node which isn't required here) quietly to stderr, then emit one
# JSON line to stdout. Falls back to an existing dist/ if the build can't run.
# Driven by tools/bench.py; see build/bench/README.md.
bench:
	@npx tsc --build src 1>&2 || echo "tsc build skipped; using existing dist/" 1>&2
	@node bench/bench.js

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
#
# npm auth: `npm publish` reads the per-registry token from the
# npm_config_//registry.npmjs.org/:_authToken env var, which a headless run
# supplies with `boru vault exec --for=npm <alias> -- make publish-ts` (the
# recipe sets that exact var). The git tag push needs GitHub auth: when
# GH_TOKEN/GITHUB_TOKEN is present we push over HTTPS carrying the credential
# in an Authorization header (kept out of the URL, .git/config, and argv);
# otherwise we fall back to the `origin` remote (SSH for local dev).
#
# Dry-run cooperation: `boru vault exec --dry-run` injects a fixed filler in
# place of the real token, so the whole publish can be rehearsed without
# credentials. When the npm or GitHub token is that filler we run the package
# dry-run, report what would happen, and exit 0 — nothing published, no tag.
#
# NEEDS npm >= 11.19. `npm stage publish` stages the tarball and defers the
# 2FA proof-of-presence to an approval step, which is what the trusted
# publisher on npmjs.com grants alongside plain `npm publish`. It arrived
# between 11.9.0 and 11.19.1: on anything older npm answers
#
#   Unknown command: "stage"
#
# which reads exactly like a typo and invites the "fix" of deleting the
# word. It is not a typo. Upgrade npm instead. (CI does not use this path
# at all -- .github/workflows/publish.yml publishes over OIDC with plain
# `npm publish`, where there is no human to prove presence.)
#
# Reading the slash/colon-named npm auth var needs a shell that preserves
# non-identifier env names across exec (bash does; dash/busybox sh drop them).
SHELL := /bin/bash
VERSION := $(shell node -p "require('./package.json').version" 2>/dev/null)
TAG := typescript/v$(VERSION)
# (The literal keeps the legacy AQL name: it must match the boru vault's dryRunFiller constant.)
BORU_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: build test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump package.json version first"; exit 1; fi
	@set -e; \
	npmtok="$$(printenv 'npm_config_//registry.npmjs.org/:_authToken' 2>/dev/null || true)"; \
	ghtok="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$npmtok" = "$(BORU_DRY_RUN_FILLER)" ] || [ "$$ghtok" = "$(BORU_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] boru filler token detected: rehearsing the package; nothing published, no $(TAG) tag."; \
	  npm stage publish --dry-run --access public --registry https://registry.npmjs.org; \
	  exit 0; \
	fi; \
	npm stage publish --access public --registry https://registry.npmjs.org; \
	echo "tag: $(TAG)"; \
	git tag -a "$(TAG)" -m "typescript v$(VERSION)"; \
	if [ -n "$$ghtok" ]; then \
	  echo "push: $(TAG) -> github.com/voxgig/struct (HTTPS, token auth)"; \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$ghtok" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  echo "push: $(TAG) -> origin (ssh)"; \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Published @voxgig/struct@$(VERSION) + tag $(TAG)."
