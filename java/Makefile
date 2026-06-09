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

# Release: deploy to Maven Central (OSSRH) via the `release` profile, then
# tag java/vX.Y.Z (version = first <version> in pom.xml, the project version).
# Needs auth: <server> credentials (id=central) in ~/.m2/settings.xml plus a
# GPG signing key (the release profile signs in the verify phase).
VERSION := $(shell grep -m1 "<version>" pom.xml | sed -E "s/.*<version>([^<]+)<.*/\1/")
publish: test
	mvn -q -Prelease deploy
	@if git rev-parse -q --verify "refs/tags/java/v$(VERSION)" >/dev/null; then \
	  echo "tag java/v$(VERSION) already exists — bump pom.xml version first"; exit 1; fi
	git tag -a "java/v$(VERSION)" -m "java v$(VERSION)"
	git push origin "java/v$(VERSION)"
