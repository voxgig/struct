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

# Release: publish to the Sonatype Central Portal via the vanniktech plugin
# (OSSRH was retired 2025-06-30), then tag kotlin/vX.Y.Z (version from
# build.gradle.kts). Auth (from the aql vault at release time, none on disk),
# as ORG_GRADLE_PROJECT_* env vars the plugin reads as Gradle properties:
#   ORG_GRADLE_PROJECT_mavenCentralUsername / ...Password   Portal user token
#   ORG_GRADLE_PROJECT_signingInMemoryKeyPassword           GPG key passphrase
#   SIGNING_KEY_B64                                          base64 of the armored
#       GPG secret key; decoded below into ORG_GRADLE_PROJECT_signingInMemoryKey.
#       base64 (not raw armor) so the multi-line key survives the vault->env
#       hop intact — Gradle's signer rejects a key whose newlines got mangled.
#   GITHUB_TOKEN                                             pushes the git tag
# Prereq: the com.voxgig namespace verified on the Portal; produce SIGNING_KEY_B64
# with `gpg --armor --export-secret-keys <KEYID> | base64`.
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
	if [ -n "$$SIGNING_KEY_B64" ]; then \
	  ORG_GRADLE_PROJECT_signingInMemoryKey=$$(printf '%s' "$$SIGNING_KEY_B64" | base64 -d); \
	  export ORG_GRADLE_PROJECT_signingInMemoryKey; \
	fi; \
	$(GRADLE) publishToMavenCentral; \
	git tag -a "$(TAG)" -m "kotlin v$(VERSION)"; \
	if [ -n "$$token" ]; then \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$token" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Published artifact + tag $(TAG)."
