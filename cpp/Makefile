JSON_INC ?= /usr/include
# Try common locations if the default is missing.
EXTRA_INC := -I $(JSON_INC) -I /opt/homebrew/include -I /usr/local/include

CXXFLAGS_COMMON := --std=c++17 -Wall -Wextra -Wno-unused-parameter

CPP_SOURCES := $(wildcard src/*.hpp tests/*.hpp tests/*.cpp)

.PHONY: build smoke test corpus check_leak sanitize lint tidy format-check clean reset inspect publish

# Default: compile and run the smoke test plus the full corpus driver.
build: smoke corpus

smoke:
	g++ tests/smoke.cpp $(CXXFLAGS_COMMON) -I ./src -I ./tests $(EXTRA_INC) -o smoke.out && ./smoke.out

corpus:
	g++ tests/struct_corpus_test.cpp $(CXXFLAGS_COMMON) -I ./src -I ./tests $(EXTRA_INC) -o corpus.out && ./corpus.out

test: build

# Backwards-compatible alias used by existing CI scripts.
compile_and_run_tests: corpus

check_leak: corpus
	valgrind --leak-check=full --show-leak-kinds=all ./corpus.out

sanitize:
	g++ tests/struct_corpus_test.cpp $(CXXFLAGS_COMMON) -fsanitize=address,undefined -g -I ./src -I ./tests $(EXTRA_INC) -o sanitize.out && ./sanitize.out

# Code quality: clang-tidy (static analysis) + clang-format check.
lint: tidy format-check

tidy:
	clang-tidy tests/struct_corpus_test.cpp tests/smoke.cpp -- \
	  $(CXXFLAGS_COMMON) -I ./src -I ./tests $(EXTRA_INC)

format-check:
	clang-format --dry-run --Werror $(CPP_SOURCES)

clean:
	rm -f out.out corpus.out smoke.out sanitize.out corpus-scoreboard.json

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
# Headless publish: `aql vault exec --for=github <alias> -- make publish-cpp`
# injects GH_TOKEN/GITHUB_TOKEN; the tag is pushed over HTTPS via an
# Authorization header (kept out of the URL, .git/config, and argv), else the
# origin SSH remote. `aql vault exec --dry-run` injects a filler we detect to
# rehearse (no tag). set -e: a failed push never leaves a tag behind.
VERSION := $(shell cat VERSION)
TAG := cpp/v$(VERSION)
AQL_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump cpp/VERSION first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(AQL_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] aql filler token detected: would tag $(TAG) and push it over"; \
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
