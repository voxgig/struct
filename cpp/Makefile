JSON_INC ?= $(HOME)/Project/json/single_include
# Try common locations if the default is missing.
EXTRA_INC := -I $(JSON_INC) -I /opt/homebrew/include -I /usr/local/include -I $(HOME)/Projects/json/single_include

compile_and_run_tests:
	g++ tests/test_voxgig_struct.cpp -Werror --std=c++11 -I ./src -I ./tests $(EXTRA_INC) -o out.out && ./out.out

bench: walk_bench
	WALK_BENCH=$${WALK_BENCH:-1} ./walk_bench.out

walk_bench:
	g++ tests/walk_bench.cpp -O2 --std=c++11 -I ./src -I ./tests $(EXTRA_INC) -o walk_bench.out

check_leak:
	valgrind --leak-check=full --show-leak-kinds=all ./out.out
