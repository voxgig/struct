.PHONY: inspect build test lint walk-bench clean reset audit

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

# Code quality: RuboCop linter/formatter.
lint:
	bundle exec rubocop

walk-bench:
	WALK_BENCH=1 ruby walk_bench.rb

clean:
	rm -rf pkg

reset: clean
	rm -rf vendor

# Supply-chain: scan dependencies against the ruby-advisory-db.
# Requires: gem install bundler-audit
audit:
	bundle-audit check --update
