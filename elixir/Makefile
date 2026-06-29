# Makefile for the Elixir port of voxgig/struct.
# Requires Elixir (`elixir` / `elixirc`) on PATH. No third-party dependencies.

.PHONY: test lint build inspect clean reset publish format

# Run the shared JSON corpus through the Elixir implementation.
test:
	elixir test/runner.exs

# "Lint": compile the library with warnings (a clean compile means it is sound).
lint:
	elixirc lib/voxgig_struct.ex -o /tmp/voxgig_struct_build

# Compile the library as a build smoke-test.
build:
	elixirc lib/voxgig_struct.ex -o /tmp/voxgig_struct_build

format:
	mix format --check-formatted lib/voxgig_struct.ex 2>/dev/null || true

inspect:
	@elixir --version

clean:
	rm -rf _build /tmp/voxgig_struct_build Elixir.*.beam

reset: clean

# Release: Hex registry upload is a documented manual step for now; this
# target cuts the elixir/vX.Y.Z git tag headlessly.
# Headless: `aql vault exec --for=github <alias> -- make publish-elixir` injects
# GH_TOKEN/GITHUB_TOKEN; the tag is pushed over HTTPS via an Authorization header
# (kept out of the URL, .git/config, and argv), else the origin SSH remote.
# `aql vault exec --dry-run` injects a filler we detect to rehearse (no tag).
# set -e: a failed push never leaves a tag behind.
VERSION := $(shell cat VERSION)
TAG := elixir/v$(VERSION)
AQL_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump elixir/VERSION first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(AQL_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] aql filler token detected: would tag $(TAG) and push it over"; \
	  echo "[dry-run] HTTPS to github.com/voxgig/struct — no tag created, nothing pushed."; \
	  exit 0; \
	fi; \
	echo "tag: $(TAG)"; \
	git tag -a "$(TAG)" -m "elixir v$(VERSION)"; \
	if [ -n "$$token" ]; then \
	  echo "push: $(TAG) -> github.com/voxgig/struct (HTTPS, token auth)"; \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$token" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  echo "push: $(TAG) -> origin (ssh)"; \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Tagged $(TAG). Hex upload (manual): mix hex.publish"
