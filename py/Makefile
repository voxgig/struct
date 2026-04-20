.PHONY: inspect build test bench clean reset

inspect:
	@echo "Python version:"
	@python3 --version
	@echo ""
	@echo "Project version:"
	@python3 -c "import voxgig_struct; print(getattr(voxgig_struct, '__version__', 'unknown'))" 2>/dev/null || echo "unknown"

build:
	@echo "No build step for Python"

test:
	python3 -m unittest discover -s tests

bench:
	WALK_BENCH=1 python3 -m unittest discover -s tests -p 'test_walk_bench.py' -v

bench-quick:
	WALK_BENCH=1 \
	  WALK_BENCH_VD_DEPTH=16 WALK_BENCH_RUNS_VD=3 WALK_BENCH_WARMUP=1 \
	  WALK_BENCH_RUNS_WD=5 WALK_BENCH_RUNS_VW=5 \
	  python3 -m unittest discover -s tests -p 'test_walk_bench.py' -v

clean:
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	rm -rf *.egg-info dist build

reset: clean
