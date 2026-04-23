.PHONY: inspect build test walk-bench clean reset

inspect:
	@echo "Ruby version:"
	@ruby --version
	@echo ""
	@echo "Project version:"
	@ruby -e "puts Gem::Specification.load(Dir['*.gemspec'].first).version" 2>/dev/null || echo "unknown"

build:
	@echo "No build step for Ruby"

test:
	ruby test_voxgig_struct.rb

walk-bench:
	WALK_BENCH=1 ruby walk_bench.rb

clean:
	rm -rf pkg

reset: clean
	rm -rf vendor
