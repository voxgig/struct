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
publish: test
	$(GRADLE) publish
	@if git rev-parse -q --verify "refs/tags/kotlin/v$(VERSION)" >/dev/null; then \
	  echo "tag kotlin/v$(VERSION) already exists — bump build.gradle.kts version first"; exit 1; fi
	git tag -a "kotlin/v$(VERSION)" -m "kotlin v$(VERSION)"
	git push origin "kotlin/v$(VERSION)"
