# Makefile for the Scala port of voxgig/struct.
# Requires `scala-cli` + a JDK on PATH (build/lint/test/publish all use it).
# No third-party libraries.

SRC = src/voxgig_struct.scala

# The corpus runner is voxgig/omni, consumed as a local checkout - it is not
# published to Maven Central. $OMNI_HOME first, then sibling paths, taking the
# first directory that carries spec/fib.json.
#
# Its sources are handed to scala-cli alongside the TESTS only: `make build`
# and `make lint` compile src/ without it, and nothing published names omni
# (register 4.13).
#
# $OMNI_HOME is resolved by the SHELL, not by make's `wildcard`/`foreach`.
# Those are whitespace-delimited, so a path with a space ("C:/Users/Ann
# Smith/omni") splits into two candidates that both miss - and the result is
# not an error but a silent fallthrough to the next candidate, a DIFFERENT
# checkout. `$$OMNI_HOME` reaches the shell as the raw environment value. The
# sibling candidates are fixed literals with no spaces, so they stay here.
OMNI_SIBLINGS := ../../omni ../../../omni /workspace/omni /home/user/omni
OMNI_DIR := $(or \
  $(shell [ -n "$$OMNI_HOME" ] && [ -f "$$OMNI_HOME/spec/fib.json" ] && printf '%s' "$$OMNI_HOME"),\
  $(firstword $(foreach d,$(OMNI_SIBLINGS),$(if $(wildcard $(d)/spec/fib.json),$(d)))))

# The omni sources are kept OUT of this list and quoted at the use site: a
# make variable is a whitespace-delimited word list, so a spaced $(OMNI_DIR)
# would reach scala-cli as two separate paths.
TESTSRC = $(SRC) test/runner.scala

.PHONY: test bench lint build inspect clean reset publish omni-check

# Fail with the reason rather than "Not found: voxgig.omni".
omni-check:
	@if [ -z "$(OMNI_DIR)" ]; then \
	  echo "struct: voxgig/omni checkout not found - set OMNI_HOME."; \
	  echo "  The tests run on the shared runner; the library itself does not."; \
	  echo "  git clone https://github.com/voxgig/omni ../../omni"; \
	  exit 1; \
	fi

# Run the shared JSON corpus through the Scala implementation, on voxgig/omni.
# (The classic `scala -cp out Runner` runner was removed in Scala 3.5+, where
# `scala` is the scala-cli launcher and no longer runs a main from a classpath.)
test: omni-check
	scala-cli run $(TESTSRC) "$(OMNI_DIR)/scala/src" --main-class Runner

# Cross-port performance harness (JSON contract; see build/bench/README.md).
# Uses the Scala 3 compiler (scalac) + java rather than scala-cli, so it runs
# without network access. SCALA_RUNTIME is the run classpath (scala3 + scala2
# stdlib jars); override for your install.
SCALAC ?= scalac
SCALA_RUNTIME ?= /opt/scala3/lib/scala3-library_3.jar:/opt/scala3/lib/scala-library.jar
bench:
	@mkdir -p bench/out
	@$(SCALAC) -d bench/out $(SRC) bench/bench.scala 1>&2
	@java -cp "bench/out:$(SCALA_RUNTIME)" bench

# Compiles the LIBRARY alone: nothing shipped names omni (register 4.13).
build:
	scala-cli compile $(SRC)

# "Lint": compile the library (a clean compile means the code type-checks).
# scalafmt/scalafix can be wired into this target if available.
lint:
	scala-cli compile $(SRC) && echo ok

inspect:
	@scala-cli version 2>&1 | head -2

clean:
	rm -rf out out-lint .scala-build .bsp src/.scala-build src/.bsp

reset: clean

# Release: build + sign + publish to Maven Central (Sonatype Central Portal)
# with scala-cli — the port has no sbt/mill project, just plain .scala — then
# tag scala/vX.Y.Z. scala-cli appends the Scala 3 suffix, so the published
# artifact is com.voxgig:struct-scala_3. `--publish-repository central` targets
# the Portal's OSSRH-compat API (ossrh-staging-api.central.sonatype.com); only
# src/ is packaged (never test/runner.scala).
# Auth (from the boru vault at release time, none persisted on disk):
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
# (The literal keeps the legacy AQL name: it must match the boru vault's dryRunFiller constant.)
BORU_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump scala/VERSION first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(BORU_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] boru filler token detected: would publish to Maven Central and tag $(TAG); nothing pushed."; \
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
