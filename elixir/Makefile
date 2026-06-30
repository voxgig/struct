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

# Release: publish to Hex (mix hex.publish package — package only, so no ex_doc
# dependency), then tag elixir/vX.Y.Z (version from VERSION, via mix.exs too).
# Auth (from the aql vault at release time, none persisted on disk):
#   HEX_API_KEY    Hex key with package-publish perms (`mix hex.user key
#                  generate` or hex.pm -> Account -> generate a key)
#   GITHUB_TOKEN   pushes the git tag
# Ensures the hex archive is installed for a headless run. set -e + tag-last:
# a failed Hex upload aborts before any tag is created.
VERSION := $(shell cat VERSION)
TAG := elixir/v$(VERSION)
AQL_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump elixir/VERSION first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(AQL_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] aql filler token detected: would publish to Hex and tag $(TAG); nothing pushed."; \
	  exit 0; \
	fi; \
	mix local.hex --force >/dev/null 2>&1 || true; \
	mix hex.publish package --yes; \
	git tag -a "$(TAG)" -m "elixir v$(VERSION)"; \
	if [ -n "$$token" ]; then \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$token" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Published to Hex + tag $(TAG)."
