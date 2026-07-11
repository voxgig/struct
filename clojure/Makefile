# Makefile for the Clojure port of voxgig/struct.
# Requires the Clojure CLI (`clojure` / `clj`) and a JDK on PATH.

.PHONY: test bench lint build inspect clean reset publish

# Run the shared JSON corpus through the Clojure implementation.
test:
	clojure -M:test

# Cross-port performance harness (JSON contract; see build/bench/README.md).
# Runs clojure.main with src + bench on the classpath.
bench:
	@clojure -cp src:bench -m voxgig.bench

# "Lint": compile the library + runner namespaces. A clean load means the
# code is syntactically and structurally sound. (No third-party linter is
# required; clj-kondo can be added to the :lint alias if available.)
lint:
	clojure -M:lint -e "(require 'voxgig.struct :reload) (require 'voxgig.struct-runner :reload) (println \"ok\")"

build:
	clojure -M -e "(compile 'voxgig.struct)" 2>/dev/null || clojure -M -e "(require 'voxgig.struct)"

inspect:
	@clojure --version 2>/dev/null || true
	@java -version 2>&1 | head -1

clean:
	rm -rf .cpcache classes target

reset: clean

# Release: build the jar + pom and deploy to Clojars (clojure -T:build deploy,
# see build.clj), then cut + push the clojure/vX.Y.Z git tag.
# Auth (from the aql vault at release time, none persisted on disk):
#   CLOJARS_USERNAME / CLOJARS_PASSWORD  Clojars deploy token (deps-deploy reads
#                                        these from the env; password = token)
#   GITHUB_TOKEN                         pushes the git tag over HTTPS
# Headless: `aql vault exec ... -- make publish-clojure`. `--dry-run` injects a
# filler we detect to rehearse (no deploy, no tag). set -e + tag-last: a failed
# Clojars upload aborts before any tag is created.
# Prereq: the com.voxgig group verified on Clojars (clojars.org/verify).
VERSION := $(shell cat VERSION)
TAG := clojure/v$(VERSION)
AQL_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump clojure/VERSION first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(AQL_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] aql filler token detected: would deploy to Clojars and tag $(TAG); nothing pushed."; \
	  exit 0; \
	fi; \
	clojure -T:build deploy; \
	git tag -a "$(TAG)" -m "clojure v$(VERSION)"; \
	if [ -n "$$token" ]; then \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$token" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Published to Clojars + tag $(TAG)."
