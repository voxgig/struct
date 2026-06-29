# Makefile for the Scala port of voxgig/struct.
# Requires the Scala 3 compiler (`scalac` / `scala`) and a JDK on PATH.
# No third-party libraries.

SRC = src/voxgig_struct.scala
TESTSRC = $(SRC) test/runner.scala

.PHONY: test lint build inspect clean reset publish

# Build and run the shared JSON corpus through the Scala implementation.
test: build
	scala -cp out Runner

build:
	rm -rf out && mkdir out && scalac $(TESTSRC) -d out

# "Lint": compile the library (a clean compile means the code type-checks).
# scalafmt/scalafix can be wired into this target if available.
lint:
	rm -rf out-lint && mkdir out-lint && scalac $(SRC) -d out-lint && echo ok

inspect:
	@scalac -version 2>&1 | head -1

clean:
	rm -rf out out-lint

reset: clean

# Release: Sonatype/Maven Central registry upload is a documented manual step for
# now; this target cuts the scala/vX.Y.Z git tag headlessly.
# Headless: `aql vault exec --for=github <alias> -- make publish-scala` injects
# GH_TOKEN/GITHUB_TOKEN; the tag is pushed over HTTPS via an Authorization header
# (kept out of the URL, .git/config, and argv), else the origin SSH remote.
# `aql vault exec --dry-run` injects a filler we detect to rehearse (no tag).
# set -e: a failed push never leaves a tag behind.
VERSION := $(shell cat VERSION)
TAG := scala/v$(VERSION)
AQL_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump scala/VERSION first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(AQL_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] aql filler token detected: would tag $(TAG) and push it over"; \
	  echo "[dry-run] HTTPS to github.com/voxgig/struct — no tag created, nothing pushed."; \
	  exit 0; \
	fi; \
	echo "tag: $(TAG)"; \
	git tag -a "$(TAG)" -m "scala v$(VERSION)"; \
	if [ -n "$$token" ]; then \
	  echo "push: $(TAG) -> github.com/voxgig/struct (HTTPS, token auth)"; \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$token" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  echo "push: $(TAG) -> origin (ssh)"; \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Tagged $(TAG). Maven Central upload (manual): sbt publishSigned"
