# Makefile for the Dart port of voxgig/struct.
# Requires the Dart SDK (`dart`) on PATH. No third-party dependencies.

.PHONY: test lint build inspect clean reset publish format

# Run the shared JSON corpus through the Dart implementation.
test:
	dart run test/runner.dart

# "Lint": static analysis (a clean `dart analyze` means the code is sound).
lint:
	dart analyze

# Compile the library to a kernel snapshot as a build smoke-test.
build:
	dart compile kernel lib/voxgig_struct.dart -o /dev/null 2>/dev/null || dart analyze lib

format:
	dart format --output=none --set-exit-if-changed lib test

inspect:
	@dart --version

clean:
	rm -rf .dart_tool *.dill

reset: clean

# Release: pub.dev registry upload is a documented manual step for now; this
# target cuts the dart/vX.Y.Z git tag headlessly.
# Headless: `aql vault exec --for=github <alias> -- make publish-dart` injects
# GH_TOKEN/GITHUB_TOKEN; the tag is pushed over HTTPS via an Authorization header
# (kept out of the URL, .git/config, and argv), else the origin SSH remote.
# `aql vault exec --dry-run` injects a filler we detect to rehearse (no tag).
# set -e: a failed push never leaves a tag behind.
VERSION := $(shell grep -E '^version:' pubspec.yaml | sed -E 's/.*version:[[:space:]]*([0-9][^[:space:]]*).*/\1/')
TAG := dart/v$(VERSION)
AQL_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump pubspec.yaml version first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(AQL_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] aql filler token detected: would tag $(TAG) and push it over"; \
	  echo "[dry-run] HTTPS to github.com/voxgig/struct — no tag created, nothing pushed."; \
	  exit 0; \
	fi; \
	echo "tag: $(TAG)"; \
	git tag -a "$(TAG)" -m "dart v$(VERSION)"; \
	if [ -n "$$token" ]; then \
	  echo "push: $(TAG) -> github.com/voxgig/struct (HTTPS, token auth)"; \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$token" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  echo "push: $(TAG) -> origin (ssh)"; \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Tagged $(TAG). pub.dev upload (manual): dart pub publish"
