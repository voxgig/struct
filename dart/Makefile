# Makefile for the Dart port of voxgig/struct.
# Requires the Dart SDK (`dart`) on PATH. No third-party dependencies.

.PHONY: test bench lint build inspect clean reset publish format deps

# The corpus runner is voxgig/omni, taken from its release tag: pubspec.yaml
# declares `voxgig_omni` under `dev_dependencies` as a git dependency on
# `dart/v0.1.0`, and pubspec.lock records the commit that resolved to. No
# checkout beside this one, no $OMNI_HOME, and no generated override file -
# `dart pub get` fetches it, and a run here is reproducible from this repo's
# commit alone.
#
# `dev_dependencies` is also the isolation device: pub never installs one
# transitively, so nothing that depends on voxgig_struct can reach omni
# (register 4.13), and `make build` still proves it by compiling lib/ alone.
#
# pubspec.lock is NOT tracked - this package is a published library, and pub
# says a library does not commit one - so the lock cannot be the pin here the
# way corpus/Cargo.lock is for rust. The tag is resolved afresh on every
# checkout, and a moved tag would silently swap the runner. So the resolved
# ref is checked against a sha pinned here, which is the same guarantee
# clojure gets from `:git/sha` and lean from its fetch check.
OMNI_TAG := dart/v0.1.0
OMNI_SHA := a710fcda81b0a72a5e98322cac0af56ab8c2d959

deps:
	@dart pub get >/dev/null
	@got=$$(awk '/^  voxgig_omni:/{f=1} f && /resolved-ref:/{print $$2; exit}' pubspec.lock); \
	if [ "$$got" != "$(OMNI_SHA)" ]; then \
	  echo "struct: $(OMNI_TAG) resolved to $$got, not the pinned $(OMNI_SHA)."; \
	  echo "  The tag moved. Refusing to test against an omni this repo has not pinned."; \
	  exit 1; \
	fi

# Run the shared JSON corpus through the Dart implementation, on voxgig/omni.
test: deps
	dart run test/runner.dart

# Cross-port performance harness (JSON contract; see build/bench/README.md).
bench:
	@dart run bench/bench.dart

# "Lint": static analysis (a clean `dart analyze` means the code is sound).
# The runner imports omni, so this needs the dependency resolved too.
lint: deps
	dart analyze

# Compile the library to a kernel snapshot as a build smoke-test.
build:
	dart compile kernel lib/voxgig_struct.dart -o /dev/null 2>/dev/null || dart analyze lib

# No `deps` prerequisite: formatting only parses the files, so it needs no
# package resolution at all - and the README says omni is for tests.
format:
	dart format --output=none --set-exit-if-changed lib test

inspect:
	@dart --version

clean:
	rm -rf .dart_tool *.dill pubspec_overrides.yaml

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
# (The literal keeps the legacy AQL name: it must match the boru vault's dryRunFiller constant.)
BORU_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump pubspec.yaml version first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(BORU_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] boru filler token detected: would publish to pub.dev and tag $(TAG); nothing pushed."; \
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
