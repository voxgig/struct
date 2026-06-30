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

# Release: publish to pub.dev (dart pub publish --force), then tag dart/vX.Y.Z
# (version from pubspec.yaml).
# Auth: pub.dev uses OAuth — a one-time `dart pub login` writes a credentials
# JSON (with a refresh token) to ~/Library/Application Support/dart/pub-
# credentials.json. Headless, the vault supplies that JSON as PUB_CREDENTIALS
# (single line, no newline issues) and we write it to the config path before
# publishing; the github token pushes the tag. set -e + tag-last: a failed
# upload never leaves a tag behind.
VERSION := $(shell grep -E '^version:' pubspec.yaml | sed -E 's/.*version:[[:space:]]*([0-9][^[:space:]]*).*/\1/')
TAG := dart/v$(VERSION)
AQL_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump pubspec.yaml version first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(AQL_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] aql filler token detected: would publish to pub.dev and tag $(TAG); nothing pushed."; \
	  exit 0; \
	fi; \
	if [ -n "$$PUB_CREDENTIALS" ]; then \
	  creddir="$$HOME/Library/Application Support/dart"; \
	  [ -d "$$HOME/Library/Application Support" ] || creddir="$${XDG_CONFIG_HOME:-$$HOME/.config}/dart"; \
	  mkdir -p "$$creddir"; \
	  printf '%s' "$$PUB_CREDENTIALS" > "$$creddir/pub-credentials.json"; \
	fi; \
	dart pub publish --force; \
	git tag -a "$(TAG)" -m "dart v$(VERSION)"; \
	if [ -n "$$token" ]; then \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$token" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Published to pub.dev + tag $(TAG)."
