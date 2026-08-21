JSON_INC ?= /usr/include
# Try common locations if the default is missing.
EXTRA_INC := -I $(JSON_INC) -I /opt/homebrew/include -I /usr/local/include

CXXFLAGS_COMMON := --std=c++17 -Wall -Wextra -Wno-unused-parameter

CPP_SOURCES := $(wildcard src/*.hpp tests/*.hpp tests/*.cpp)

# The corpus runner is voxgig/omni, consumed as a local checkout - it is
# header-only and not published. $OMNI_HOME first, then sibling paths, taking
# the first directory that carries spec/fib.json.
#
# It is on the include path of the TEST translation units only. `make build`
# compiles the smoke test, which does not include it, and nothing in src/
# names omni (register 4.13).
OMNI_CANDIDATES := $(OMNI_HOME) ../../omni ../../../omni /workspace/omni /home/user/omni
OMNI_DIR := $(firstword $(foreach d,$(OMNI_CANDIDATES),$(if $(wildcard $(d)/spec/fib.json),$(d))))
OMNI_INC := $(if $(OMNI_DIR),-I $(OMNI_DIR)/cpp/src)

# Placing omni-check above `build` made it the first ordinary target, and so
# make's default goal: a bare `make` ran the omni probe instead of building
# the smoke test, and failed outright with no checkout. Say it explicitly.
.DEFAULT_GOAL := build

.PHONY: build smoke test bench corpus client check_leak sanitize lint tidy format-check clean reset inspect publish omni-check

# Fail with the reason rather than a page of "omni.hpp: No such file".
omni-check:
	@if [ -z "$(OMNI_DIR)" ]; then \
	  echo "struct: voxgig/omni checkout not found - set OMNI_HOME."; \
	  echo "  The tests run on the shared runner; the library itself does not."; \
	  echo "  git clone https://github.com/voxgig/omni ../../omni"; \
	  exit 1; \
	fi

# Default: the smoke test, which needs nothing but this port.
build: smoke

smoke:
	g++ tests/smoke.cpp $(CXXFLAGS_COMMON) -I ./src -I ./tests $(EXTRA_INC) -o smoke.out && ./smoke.out

corpus: omni-check
	g++ tests/struct_corpus_test.cpp $(CXXFLAGS_COMMON) -I ./src -I ./tests $(OMNI_INC) $(EXTRA_INC) -o corpus.out && ./corpus.out

client: omni-check
	g++ tests/client_test.cpp $(CXXFLAGS_COMMON) -I ./src -I ./tests $(OMNI_INC) $(EXTRA_INC) -o client.out && ./client.out

test: smoke corpus client

# Cross-port performance harness (JSON contract; see build/bench/README.md).
# -O2 for representative timings; compile log to stderr.
bench:
	@g++ bench/bench.cpp $(CXXFLAGS_COMMON) -O2 -I ./src $(EXTRA_INC) -o bench/bench.out 1>&2
	@./bench/bench.out

# Backwards-compatible alias used by existing CI scripts.
compile_and_run_tests: corpus

check_leak: corpus
	valgrind --leak-check=full --show-leak-kinds=all ./corpus.out

sanitize: omni-check
	g++ tests/struct_corpus_test.cpp $(CXXFLAGS_COMMON) -fsanitize=address,undefined -g -I ./src -I ./tests $(OMNI_INC) $(EXTRA_INC) -o sanitize.out && ./sanitize.out

# Code quality: clang-tidy (static analysis) + clang-format check.
lint: tidy format-check

tidy: omni-check
	clang-tidy tests/struct_corpus_test.cpp tests/client_test.cpp tests/smoke.cpp -- \
	  $(CXXFLAGS_COMMON) -I ./src -I ./tests $(OMNI_INC) $(EXTRA_INC)

format-check:
	clang-format --dry-run --Werror $(CPP_SOURCES)

clean:
	rm -f out.out corpus.out client.out smoke.out sanitize.out corpus-scoreboard.json

reset: clean

inspect:
	@echo "g++ version:"
	@g++ --version | head -1
	@echo ""
	@echo "nlohmann/json header:"
	@find /usr/include /usr/local/include /opt/homebrew/include -name 'json.hpp' -path '*nlohmann*' 2>/dev/null | head -1

# Release: C++ has no registry — publishing IS the git tag. The port lives in a
# subdirectory, so the tag MUST be the `cpp/vX.Y.Z` form. Version is in the
# VERSION file.
#
# Headless publish: `boru vault exec --for=github <alias> -- make publish-cpp`
# injects GH_TOKEN/GITHUB_TOKEN; the tag is pushed over HTTPS via an
# Authorization header (kept out of the URL, .git/config, and argv), else the
# origin SSH remote. `boru vault exec --dry-run` injects a filler we detect to
# rehearse (no tag). set -e: a failed push never leaves a tag behind.
VERSION := $(shell cat VERSION)
TAG := cpp/v$(VERSION)
# (The literal keeps the legacy AQL name: it must match the boru vault's dryRunFiller constant.)
BORU_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump cpp/VERSION first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(BORU_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] boru filler token detected: would tag $(TAG) and push it over"; \
	  echo "[dry-run] HTTPS to github.com/voxgig/struct — no tag created, nothing pushed."; \
	  exit 0; \
	fi; \
	echo "tag: $(TAG)"; \
	git tag -a "$(TAG)" -m "cpp v$(VERSION)"; \
	if [ -n "$$token" ]; then \
	  echo "push: $(TAG) -> github.com/voxgig/struct (HTTPS, token auth)"; \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$token" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  echo "push: $(TAG) -> origin (ssh)"; \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Published $(TAG). Header-only; no central registry — consumers vendor the headers or pin this tag."
