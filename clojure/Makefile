# Makefile for the Clojure port of voxgig/struct.
# Requires the Clojure CLI (`clojure` / `clj`) and a JDK on PATH.

.PHONY: test bench lint build inspect clean reset publish omni-check

# The corpus runner is voxgig/omni, consumed as a local checkout - it is not
# published to Clojars. $OMNI_HOME first, then sibling paths, taking the first
# directory that carries spec/fib.json.
#
# It goes on the TEST classpath only, through an :omni alias minted here on the
# command line as a :local/root dependency: `deps.edn` never names it, so
# nothing the published jar carries depends on omni (register 4.13) - and
# `make build` compiles src/ alone.
OMNI_CANDIDATES := $(OMNI_HOME) ../../omni ../../../omni /workspace/omni /home/user/omni
OMNI_DIR := $(firstword $(foreach d,$(OMNI_CANDIDATES),$(if $(wildcard $(d)/spec/fib.json),$(d))))
#
# The path is spliced into an EDN *string literal*, so it must carry forward
# slashes. On Windows $OMNI_HOME arrives as `D:\a\struct\struct/.omni` and the
# reader rejects the backslash escapes before it ever looks at the path:
#
#     Unsupported escape character: \a
#
# The JVM accepts forward slashes on Windows, so normalising is enough. This is
# a no-op on a POSIX path, which has no backslashes to substitute.
OMNI_EDN_DIR := $(subst \,/,$(OMNI_DIR))
OMNI_ALIAS = -Sdeps '{:aliases {:omni {:extra-deps {voxgig/omni {:local/root "$(OMNI_EDN_DIR)/clojure"}}}}}'

# Fail with the reason rather than "Could not locate voxgig/omni/runner".
omni-check:
	@if [ -z "$(OMNI_DIR)" ]; then \
	  echo "struct: voxgig/omni checkout not found - set OMNI_HOME."; \
	  echo "  The tests run on the shared runner; the library itself does not."; \
	  echo "  git clone https://github.com/voxgig/omni ../../omni"; \
	  exit 1; \
	fi

# Run the shared JSON corpus through the Clojure implementation, on voxgig/omni.
test: omni-check
	clojure $(OMNI_ALIAS) -M:test:omni

# Cross-port performance harness (JSON contract; see build/bench/README.md).
# Runs clojure.main with src + bench on the classpath.
bench:
	@clojure -cp src:bench -m voxgig.bench

# "Lint": compile the library + runner namespaces. A clean load means the
# code is syntactically and structurally sound. (No third-party linter is
# required; clj-kondo can be added to the :lint alias if available.)
# The runner requires omni, so this needs the checkout too.
lint: omni-check
	clojure $(OMNI_ALIAS) -M:lint:omni -e "(require 'voxgig.struct :reload) (require 'voxgig.struct-runner :reload) (println \"ok\")"

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
# Auth (from the boru vault at release time, none persisted on disk):
#   CLOJARS_USERNAME / CLOJARS_PASSWORD  Clojars deploy token (deps-deploy reads
#                                        these from the env; password = token)
#   GITHUB_TOKEN                         pushes the git tag over HTTPS
# Headless: `boru vault exec ... -- make publish-clojure`. `--dry-run` injects a
# filler we detect to rehearse (no deploy, no tag). set -e + tag-last: a failed
# Clojars upload aborts before any tag is created.
# Prereq: the com.voxgig group verified on Clojars (clojars.org/verify).
VERSION := $(shell cat VERSION)
TAG := clojure/v$(VERSION)
# (The literal keeps the legacy AQL name: it must match the boru vault's dryRunFiller constant.)
BORU_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump clojure/VERSION first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(BORU_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] boru filler token detected: would deploy to Clojars and tag $(TAG); nothing pushed."; \
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
