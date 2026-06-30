.PHONY: inspect build test lint checkstyle spotbugs clean reset publish

inspect:
	@echo "Java version:"
	@java -version 2>&1 | head -1
	@echo ""
	@echo "Maven version:"
	@mvn -v | head -1

build:
	mvn -q -DskipTests compile

test:
	mvn -q test

# Code quality: Checkstyle (style) + SpotBugs (bug pattern detection).
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
# Auth (all from the aql vault at release time, none persisted on disk):
#   CENTRAL_USERNAME / CENTRAL_PASSWORD  Portal user token (release-settings.xml)
#   MAVEN_GPG_PASSPHRASE                 unlocks the GPG signing key
#   GITHUB_TOKEN                         pushes the git tag over HTTPS
# Prereqs: the com.voxgig namespace verified on the Portal, and the GPG secret
# key imported into the local keyring + its public key on a keyserver.
VERSION := $(shell grep -m1 "<version>" pom.xml | sed -E "s/.*<version>([^<]+)<.*/\1/")
TAG := java/v$(VERSION)
AQL_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump pom.xml first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(AQL_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] aql filler token detected: would publish artifact and tag $(TAG); nothing pushed."; \
	  exit 0; \
	fi; \
	mvn -q -Prelease -s release-settings.xml deploy; \
	git tag -a "$(TAG)" -m "java v$(VERSION)"; \
	if [ -n "$$token" ]; then \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$token" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Published artifact + tag $(TAG)."
