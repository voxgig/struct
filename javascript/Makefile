.PHONY: inspect build test tag bench lint format-check clean reset audit publish

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

# Performance bench: emit one JSON line to stdout (see build/bench/README.md).
bench:
	@node bench/bench.js

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
#
# npm auth: `npm publish` reads the per-registry token from the
# npm_config_//registry.npmjs.org/:_authToken env var, which a headless run
# supplies with `boru vault exec --for=npm <alias> -- make publish-javascript`
# (the recipe sets that exact var). The git tag push needs GitHub auth: with
# GH_TOKEN/GITHUB_TOKEN present we push over HTTPS carrying the credential in an
# Authorization header (kept out of the URL, .git/config, and argv); otherwise
# we fall back to the origin SSH remote.
#
# Dry-run cooperation: `boru vault exec --dry-run` injects a fixed filler in
# place of the real token; when the npm or GitHub token is that filler we run
# the package dry-run, report what would happen, and exit 0 — nothing
# published, no tag.
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
TAG := javascript/v$(VERSION)
# (The literal keeps the legacy AQL name: it must match the boru vault's dryRunFiller constant.)
BORU_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
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
	echo "Staged @voxgig/structjs@$(VERSION). NOT published yet, and NOT tagged."; \
	echo "  1. approve it:  npm stage approve   (npm stage list shows the id)"; \
	echo "  2. then tag it: make -C javascript tag"

# THE TAG IS A SECOND COMMAND, BECAUSE STAGING IS NOT PUBLISHING.
# `npm stage publish` defers the 2FA proof-of-presence: it uploads the
# tarball and stops, and `npm stage approve` is what puts the version on
# the registry. This recipe used to tag and print "Published" the moment
# staging returned, so a rejected, expired or simply forgotten approval
# left a release tag with no release behind it -- and the existing-tag
# guard above then refused the retry.
#
# So the tag waits for the registry to actually serve the version. That
# is the same order .github/workflows/publish.yml keeps for the OIDC
# path, where the tag job `needs` a successful publish: a tag only ever
# exists for a version a consumer can install.
tag:
	@set -e; \
	if ! npm view "@voxgig/structjs@$(VERSION)" version >/dev/null 2>&1; then \
	  echo "@voxgig/structjs@$(VERSION) is not on the registry."; \
	  echo "If you staged it, approve it first: npm stage approve"; \
	  exit 1; \
	fi; \
	if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "$(TAG) already exists; nothing to do"; exit 0; fi; \
	ghtok="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	git tag -a "$(TAG)" -m "javascript v$(VERSION)"; \
	if [ -n "$$ghtok" ]; then \
	  echo "push: $(TAG) -> github.com/voxgig/struct (HTTPS, token auth)"; \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$ghtok" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  echo "push: $(TAG) -> origin (ssh)"; \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Published @voxgig/structjs@$(VERSION) + tag $(TAG)."
