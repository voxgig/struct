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

# The corpus runner is voxgig/omni, consumed as a local checkout - it is not
# published, and C has no registry to publish it to. $OMNI_HOME first, then
# sibling paths, taking the first directory that carries spec/fib.json.
#
# It is compiled into the TEST binaries only. `make build` builds src/ alone,
# and nothing in the shipped library names omni (register 4.13).
OMNI_CANDIDATES := $(OMNI_HOME) ../../omni ../../../omni /workspace/omni /home/user/omni
OMNI_DIR := $(firstword $(foreach d,$(OMNI_CANDIDATES),$(if $(wildcard $(d)/spec/fib.json),$(d))))
OMNI_SOURCES := $(wildcard $(OMNI_DIR)/c/src/*.c)
OMNI_INC := $(if $(OMNI_DIR),-I $(OMNI_DIR)/c/src)
OMNI_OBJ_DIR := .omni-obj
OMNI_OBJS := $(addprefix $(OMNI_OBJ_DIR)/,$(notdir $(OMNI_SOURCES:.c=.o)))

# omni is compiled on its OWN include path, never with `-I ./src`.
#
# `-I` directories are searched for angle-bracket includes too, and this port
# ships `src/regex.h`. Compiling omni's `util.c` with `-I ./src` on the command
# line made its `#include <regex.h>` resolve to that file instead of POSIX's,
# and `regex_t` stopped existing. Same shape as the shadowing register 4.15
# records for lua, in the other direction: there a shim put omni's `src/` on a
# consumer's module path; here a consumer put its own `src/` on omni's.
$(OMNI_OBJ_DIR)/%.o: $(OMNI_DIR)/c/src/%.c
	@mkdir -p $(OMNI_OBJ_DIR)
	$(CC) -c $< $(CFLAGS_COMMON) $(CFLAGS_DEBUG) -I $(OMNI_DIR)/c/src -o $@

# Placing omni-check above `build` made it the first ordinary target, and so
# make's default goal: a bare `make` ran the omni probe instead of building,
# and failed outright with no checkout. Say the default explicitly.
.DEFAULT_GOAL := build

.PHONY: build smoke test bench corpus client check_leak sanitize lint tidy format format-check clean reset inspect publish omni-check

# Fail with the reason rather than a page of "omni.h: No such file".
omni-check:
	@if [ -z "$(OMNI_DIR)" ]; then \
	  echo "struct: voxgig/omni checkout not found - set OMNI_HOME."; \
	  echo "  The tests run on the shared runner; the library itself does not."; \
	  echo "  git clone https://github.com/voxgig/omni ../../omni"; \
	  exit 1; \
	fi

# Default: compile the library. The tests need omni; this does not.
build:
	$(CC) -c $(C_SOURCES) $(CFLAGS_COMMON) $(CFLAGS_DEBUG) -I ./src $(EXTRA_INC)
	@rm -f *.o

smoke:
	$(CC) tests/smoke.c $(C_SOURCES) $(CFLAGS_COMMON) $(CFLAGS_DEBUG) -I ./src $(EXTRA_INC) -o smoke.out $(LDLIBS) && ./smoke.out

corpus: omni-check $(OMNI_OBJS)
	$(CC) tests/struct_corpus_test.c $(C_SOURCES) $(OMNI_OBJS) $(CFLAGS_COMMON) $(CFLAGS_DEBUG) -I ./src $(OMNI_INC) $(EXTRA_INC) -o corpus.out $(LDLIBS) && ./corpus.out

client: omni-check $(OMNI_OBJS)
	$(CC) tests/client_test.c $(C_SOURCES) $(OMNI_OBJS) $(CFLAGS_COMMON) $(CFLAGS_DEBUG) -I ./src $(OMNI_INC) $(EXTRA_INC) -o client.out $(LDLIBS) && ./client.out

test: corpus client

# Cross-port performance harness (JSON contract; see build/bench/README.md).
# Release-optimised; build log to stderr so stdout is only the JSON line.
bench:
	@$(CC) bench/bench.c $(C_SOURCES) $(CFLAGS_COMMON) $(CFLAGS_RELEASE) -I ./src $(EXTRA_INC) -o bench/bench.out $(LDLIBS) 1>&2
	@./bench/bench.out

check_leak: corpus
	valgrind --leak-check=full --show-leak-kinds=all --error-exitcode=1 ./corpus.out

sanitize: omni-check $(OMNI_OBJS)
	$(CC) tests/struct_corpus_test.c $(C_SOURCES) $(OMNI_OBJS) $(CFLAGS_COMMON) -fsanitize=address,undefined -g -I ./src $(OMNI_INC) $(EXTRA_INC) -o sanitize.out $(LDLIBS) && ./sanitize.out

# Code quality: clang-tidy (static analysis) + clang-format check.
lint: format-check tidy

tidy: omni-check
	clang-tidy $(C_SOURCES) $(TEST_SOURCES) -- \
	  $(CFLAGS_COMMON) -I ./src $(OMNI_INC) $(EXTRA_INC)

format:
	clang-format -i $(ALL_SOURCES)

format-check:
	clang-format --dry-run --Werror $(ALL_SOURCES)

clean:
	rm -rf smoke.out corpus.out client.out sanitize.out corpus-scoreboard.json $(OMNI_OBJ_DIR)

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
# Headless publish: `boru vault exec --for=github <alias> -- make publish-c`
# injects GH_TOKEN/GITHUB_TOKEN; the tag is pushed over HTTPS via an
# Authorization header (kept out of the URL, .git/config, and argv), else the
# origin SSH remote. `boru vault exec --dry-run` injects a filler we detect to
# rehearse (no tag). set -e: a failed push never leaves a tag behind.
VERSION := $(shell cat VERSION)
TAG := c/v$(VERSION)
# (The literal keeps the legacy AQL name: it must match the boru vault's dryRunFiller constant.)
BORU_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump c/VERSION first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(BORU_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] boru filler token detected: would tag $(TAG) and push it over"; \
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
