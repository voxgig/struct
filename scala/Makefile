# Makefile for the Scala port of voxgig/struct.
# Requires `scalac` (build/lint) and `scala-cli` (test/publish) + a JDK on PATH.
# No third-party libraries.

SRC = src/voxgig_struct.scala
TESTSRC = $(SRC) test/runner.scala

.PHONY: test lint build inspect clean reset publish

# Run the shared JSON corpus through the Scala implementation via scala-cli.
# (The classic `scala -cp out Runner` runner was removed in Scala 3.5+, where
# `scala` is the scala-cli launcher and no longer runs a main from a classpath.)
test:
	scala-cli run $(TESTSRC) --main-class Runner

build:
	rm -rf out && mkdir out && scalac $(TESTSRC) -d out

# "Lint": compile the library (a clean compile means the code type-checks).
# scalafmt/scalafix can be wired into this target if available.
lint:
	rm -rf out-lint && mkdir out-lint && scalac $(SRC) -d out-lint && echo ok

inspect:
	@scalac -version 2>&1 | head -1

clean:
	rm -rf out out-lint .scala-build .bsp src/.scala-build src/.bsp

reset: clean

# Release: build + sign + publish to Maven Central (Sonatype Central Portal)
# with scala-cli — the port has no sbt/mill project, just plain .scala — then
# tag scala/vX.Y.Z. scala-cli appends the Scala 3 suffix, so the published
# artifact is com.voxgig:struct-scala_3. `--publish-repository central` targets
# the Portal's OSSRH-compat API (ossrh-staging-api.central.sonatype.com); only
# src/ is packaged (never test/runner.scala).
# Auth (from the aql vault at release time, none persisted on disk):
#   CENTRAL_USERNAME / CENTRAL_PASSWORD  Portal user token
#   SIGNING_KEY_B64                      base64 of the armored GPG secret key,
#       decoded to a temp file for scala-cli's Bouncy Castle signer (base64 so
#       the multi-line key survives the vault->env hop intact)
#   GPG_PASS                             GPG key passphrase
#   GITHUB_TOKEN                         pushes the git tag
# Prereq: the com.voxgig namespace verified on the Portal (already done for java).
DESC := Voxgig Struct — utilities for transforming JSON-like data structures (Scala port).
VERSION := $(shell cat VERSION)
TAG := scala/v$(VERSION)
AQL_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump scala/VERSION first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(AQL_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] aql filler token detected: would publish to Maven Central and tag $(TAG); nothing pushed."; \
	  exit 0; \
	fi; \
	keyfile=$$(mktemp); trap 'rm -f "$$keyfile"' EXIT; \
	printf '%s' "$$SIGNING_KEY_B64" | base64 -d > "$$keyfile"; \
	scala-cli --power publish src/voxgig_struct.scala \
	  --organization com.voxgig --name struct-scala --project-version "$(VERSION)" \
	  --description "$(DESC)" --url "https://github.com/voxgig/struct" \
	  --license "MIT:https://opensource.org/licenses/MIT" \
	  --vcs "github:voxgig/struct" --developer "voxgig|Voxgig|https://voxgig.com" \
	  --publish-repository central \
	  --user "env:CENTRAL_USERNAME" --password "env:CENTRAL_PASSWORD" \
	  --signer bc --secret-key "file:$$keyfile" --secret-key-password "env:GPG_PASS"; \
	git tag -a "$(TAG)" -m "scala v$(VERSION)"; \
	if [ -n "$$token" ]; then \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$token" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Published to Maven Central + tag $(TAG)."
