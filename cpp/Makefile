JSON_INC ?= /usr/include
# Try common locations if the default is missing.
EXTRA_INC := -I $(JSON_INC) -I /opt/homebrew/include -I /usr/local/include

CXXFLAGS_COMMON := --std=c++17 -Wall -Wextra -Wno-unused-parameter

.PHONY: build smoke test corpus check_leak sanitize clean reset inspect

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

clean:
	rm -f out.out corpus.out smoke.out sanitize.out corpus-scoreboard.json

reset: clean

inspect:
	@echo "g++ version:"
	@g++ --version | head -1
	@echo ""
	@echo "nlohmann/json header:"
	@find /usr/include /usr/local/include /opt/homebrew/include -name 'json.hpp' -path '*nlohmann*' 2>/dev/null | head -1
