# Makefile for the Clojure port of voxgig/struct.
# Requires the Clojure CLI (`clojure` / `clj`) and a JDK on PATH.

.PHONY: test lint build inspect clean reset publish

# Run the shared JSON corpus through the Clojure implementation.
test:
	clojure -M:test

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

# Release: Clojars registry upload is a documented manual step for now; this
# target cuts the clojure/vX.Y.Z git tag headlessly.
# Headless: `aql vault exec --for=github <alias> -- make publish-clojure` injects
# GH_TOKEN/GITHUB_TOKEN; the tag is pushed over HTTPS via an Authorization header
# (kept out of the URL, .git/config, and argv), else the origin SSH remote.
# `aql vault exec --dry-run` injects a filler we detect to rehearse (no tag).
# set -e: a failed push never leaves a tag behind.
VERSION := $(shell cat VERSION)
TAG := clojure/v$(VERSION)
AQL_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump clojure/VERSION first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(AQL_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] aql filler token detected: would tag $(TAG) and push it over"; \
	  echo "[dry-run] HTTPS to github.com/voxgig/struct — no tag created, nothing pushed."; \
	  exit 0; \
	fi; \
	echo "tag: $(TAG)"; \
	git tag -a "$(TAG)" -m "clojure v$(VERSION)"; \
	if [ -n "$$token" ]; then \
	  echo "push: $(TAG) -> github.com/voxgig/struct (HTTPS, token auth)"; \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$token" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  echo "push: $(TAG) -> origin (ssh)"; \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Tagged $(TAG). Clojars upload (manual): deps-deploy to Clojars"
