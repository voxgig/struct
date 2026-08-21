.PHONY: inspect build test setup-omni bench lint checkstyle spotbugs clean reset publish

inspect:
	@echo "Java version:"
	@java -version 2>&1 | head -1
	@echo ""
	@echo "Maven version:"
	@mvn -v | head -1

build:
	mvn -q -DskipTests compile

# -Pomni activates the profile that names the omni test dependency; see the
# comment on that profile in pom.xml for why it is not unconditional.
test: setup-omni
	mvn -q -Pomni test

# The shared test runner is voxgig/omni, a local checkout - it is not published
# to Maven Central. Build its jar and install it into the local repository, so
# the pom can name it as an ordinary test-scoped dependency rather than a
# system-scoped one (which would put it on the LIBRARY's compile classpath -
# register 4.13).
OMNI_HOME ?= $(shell for d in ../../omni ../../../omni /workspace/omni /home/user/omni; do \
	  if [ -f "$$d/spec/fib.json" ]; then echo "$$d"; break; fi; done)
setup-omni:
	@if [ -z "$(OMNI_HOME)" ] || [ ! -f "$(OMNI_HOME)/spec/fib.json" ]; then \
	  echo "struct: voxgig/omni checkout not found - set OMNI_HOME"; exit 1; fi
	@$(MAKE) -C "$(OMNI_HOME)/java" jar >/dev/null
	@mvn -q install:install-file \
	  -Dfile="$(OMNI_HOME)/java/build/omni.jar" \
	  -DgroupId=com.voxgig -DartifactId=omni -Dversion=0.1.0 -Dpackaging=jar

# Cross-port performance harness (JSON contract; see build/bench/README.md).
# Compiles the default-package Struct alongside the bench (no Maven needed).
bench:
	@mkdir -p bench/build
	@javac -d bench/build src/Struct.java bench/Bench.java 1>&2
	@java -cp bench/build Bench

# Code quality: Checkstyle (style) + SpotBugs (bug pattern detection).
# No omni prerequisite: this reaches only the `compile` phase, so it never
# compiles the test sources, and it does not activate the `omni` profile - so
# the coordinate is not even in the model. Verified with no checkout present.
lint:
	mvn -q -DskipTests compile checkstyle:check spotbugs:check

checkstyle:
	mvn -q checkstyle:check

spotbugs:
	mvn -q -DskipTests compile spotbugs:check

clean:
	mvn -q clean

reset: clean

# Release: deploy to the Sonatype Central Portal via the `release` profile
# (central-publishing-maven-plugin; OSSRH was retired 2025-06-30), then tag
# java/vX.Y.Z (version = first <version> in pom.xml, the project version).
# Auth (all from the boru vault at release time, none persisted on disk):
#   CENTRAL_USERNAME / CENTRAL_PASSWORD  Portal user token (release-settings.xml)
#   MAVEN_GPG_PASSPHRASE                 unlocks the GPG signing key
#   GITHUB_TOKEN                         pushes the git tag over HTTPS
# Prereqs: the com.voxgig namespace verified on the Portal, and the GPG secret
# key imported into the local keyring + its public key on a keyserver.
VERSION := $(shell grep -m1 "<version>" pom.xml | sed -E "s/.*<version>([^<]+)<.*/\1/")
TAG := java/v$(VERSION)
# (The literal keeps the legacy AQL name: it must match the boru vault's dryRunFiller constant.)
BORU_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump pom.xml first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(BORU_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] boru filler token detected: would publish artifact and tag $(TAG); nothing pushed."; \
	  exit 0; \
	fi; \
	mvn -q -Prelease,omni -s release-settings.xml deploy; \
	git tag -a "$(TAG)" -m "java v$(VERSION)"; \
	if [ -n "$$token" ]; then \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$token" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Published artifact + tag $(TAG)."
