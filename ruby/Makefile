.PHONY: inspect build test lint walk-bench clean reset audit publish

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

# Release: publish to RubyGems, then tag ruby/vX.Y.Z (version from the gemspec).
# Needs RubyGems auth (GEM_HOST_API_KEY env var or ~/.gem/credentials).
VERSION := $(shell grep -E "\.version\s*=" voxgig_struct.gemspec | sed -E "s/.*[\"']([^\"']+)[\"'].*/\1/")
publish: test
	gem build voxgig_struct.gemspec
	gem push voxgig_struct-$(VERSION).gem
	@if git rev-parse -q --verify "refs/tags/ruby/v$(VERSION)" >/dev/null; then \
	  echo "tag ruby/v$(VERSION) already exists — bump gemspec version first"; exit 1; fi
	git tag -a "ruby/v$(VERSION)" -m "ruby v$(VERSION)"
	git push origin "ruby/v$(VERSION)"
