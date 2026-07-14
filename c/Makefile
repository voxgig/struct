CC ?= gcc
CFLAGS_COMMON := -std=c11 -Wall -Wextra -Wpedantic -Wshadow -Wno-unused-parameter -D_GNU_SOURCE
CFLAGS_DEBUG := -O0 -g
CFLAGS_RELEASE := -O2
LDLIBS := -lm

EXTRA_INC := -I /usr/include -I /usr/local/include -I /opt/homebrew/include

C_SOURCES := $(wildcard src/*.c)
C_HEADERS := $(wildcard src/*.h)
TEST_SOURCES := $(wildcard tests/*.c)
TEST_HEADERS := $(wildcard tests/*.h)
ALL_SOURCES := $(C_SOURCES) $(C_HEADERS) $(TEST_SOURCES) $(TEST_HEADERS)

.PHONY: build smoke test bench corpus check_leak sanitize lint tidy format format-check clean reset inspect publish

# Default: compile and run the corpus driver.
build: corpus

smoke:
	$(CC) tests/smoke.c $(C_SOURCES) $(CFLAGS_COMMON) $(CFLAGS_DEBUG) -I ./src $(EXTRA_INC) -o smoke.out $(LDLIBS) && ./smoke.out

corpus:
	$(CC) tests/struct_corpus_test.c $(C_SOURCES) $(CFLAGS_COMMON) $(CFLAGS_DEBUG) -I ./src $(EXTRA_INC) -o corpus.out $(LDLIBS) && ./corpus.out

test: corpus

# Cross-port performance harness (JSON contract; see build/bench/README.md).
# Release-optimised; build log to stderr so stdout is only the JSON line.
bench:
	@$(CC) bench/bench.c $(C_SOURCES) $(CFLAGS_COMMON) $(CFLAGS_RELEASE) -I ./src $(EXTRA_INC) -o bench/bench.out $(LDLIBS) 1>&2
	@./bench/bench.out

check_leak: corpus
	valgrind --leak-check=full --show-leak-kinds=all --error-exitcode=1 ./corpus.out

sanitize:
	$(CC) tests/struct_corpus_test.c $(C_SOURCES) $(CFLAGS_COMMON) -fsanitize=address,undefined -g -I ./src $(EXTRA_INC) -o sanitize.out $(LDLIBS) && ./sanitize.out

# Code quality: clang-tidy (static analysis) + clang-format check.
lint: format-check tidy

tidy:
	clang-tidy $(C_SOURCES) $(TEST_SOURCES) -- \
	  $(CFLAGS_COMMON) -I ./src $(EXTRA_INC)

format:
	clang-format -i $(ALL_SOURCES)

format-check:
	clang-format --dry-run --Werror $(ALL_SOURCES)

clean:
	rm -f smoke.out corpus.out sanitize.out corpus-scoreboard.json

reset: clean

inspect:
	@echo "$(CC) version:"
	@$(CC) --version | head -1
	@echo ""
	@echo "No third-party deps — JSON I/O is in src/value_io.c."

# Release: C has no registry — publishing IS the git tag. The port lives in a
# subdirectory, so the tag MUST be the `c/vX.Y.Z` form. Version is in the
# VERSION file.
#
# Headless publish: `aql vault exec --for=github <alias> -- make publish-c`
# injects GH_TOKEN/GITHUB_TOKEN; the tag is pushed over HTTPS via an
# Authorization header (kept out of the URL, .git/config, and argv), else the
# origin SSH remote. `aql vault exec --dry-run` injects a filler we detect to
# rehearse (no tag). set -e: a failed push never leaves a tag behind.
VERSION := $(shell cat VERSION)
TAG := c/v$(VERSION)
AQL_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump c/VERSION first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(AQL_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] aql filler token detected: would tag $(TAG) and push it over"; \
	  echo "[dry-run] HTTPS to github.com/voxgig/struct — no tag created, nothing pushed."; \
	  exit 0; \
	fi; \
	echo "tag: $(TAG)"; \
	git tag -a "$(TAG)" -m "c v$(VERSION)"; \
	if [ -n "$$token" ]; then \
	  echo "push: $(TAG) -> github.com/voxgig/struct (HTTPS, token auth)"; \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$token" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  echo "push: $(TAG) -> origin (ssh)"; \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Published $(TAG). C has no central registry — the tag is the release (GitHub release / source tarball)."
