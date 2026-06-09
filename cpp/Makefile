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
VERSION := $(shell cat VERSION)
publish: test
	@if git rev-parse -q --verify "refs/tags/cpp/v$(VERSION)" >/dev/null; then \
	  echo "tag cpp/v$(VERSION) already exists — bump cpp/VERSION first"; exit 1; fi
	git tag -a "cpp/v$(VERSION)" -m "cpp v$(VERSION)"
	git push origin "cpp/v$(VERSION)"
	@echo "Published cpp/v$(VERSION). Header-only; no central registry — consumers vendor the headers or pin this tag."
