.PHONY: inspect build test lint clean reset publish

GRADLE ?= ./gradlew

inspect:
	@echo "Java version:"
	@java -version 2>&1 | head -1
	@echo ""
	@$(GRADLE) --version | grep -E 'Gradle|Kotlin'

build:
	$(GRADLE) compileKotlin

test:
	$(GRADLE) test

# Code quality: detekt (static analysis) + ktlint (style).
lint:
	$(GRADLE) detekt ktlintCheck

clean:
	$(GRADLE) clean

reset: clean
	rm -rf .gradle build

# Release: publish to Maven Central (OSSRH), then tag kotlin/vX.Y.Z (version
# from build.gradle.kts). Needs auth: OSSRH credentials (ossrhUsername /
# ossrhPassword Gradle properties or OSSRH_USERNAME / OSSRH_PASSWORD env vars)
# plus a GPG signing key (signing.* Gradle properties / in-memory key env).
VERSION := $(shell grep -E "^version" build.gradle.kts | sed -E "s/.*\"([^\"]+)\".*/\1/")
TAG := kotlin/v$(VERSION)
AQL_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump build.gradle.kts first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(AQL_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] aql filler token detected: would publish artifact and tag $(TAG); nothing pushed."; \
	  exit 0; \
	fi; \
	$(GRADLE) publish; \
	git tag -a "$(TAG)" -m "kotlin v$(VERSION)"; \
	if [ -n "$$token" ]; then \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$token" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Published artifact + tag $(TAG)."
