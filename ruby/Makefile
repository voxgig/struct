.PHONY: inspect build test lint bench walk-bench clean reset audit publish

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

# Cross-port performance harness (JSON contract; see build/bench/README.md).
bench:
	@ruby bench/bench.rb

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
#
# RubyGems auth: `gem push` reads GEM_HOST_API_KEY, which a headless run
# supplies with `aql vault exec --for=gem <alias> -- make publish-ruby`. The
# git tag push needs GitHub auth: with GH_TOKEN/GITHUB_TOKEN present we push
# over HTTPS carrying the credential in an Authorization header (kept out of
# the URL, .git/config, and argv); otherwise we fall back to the `origin`
# remote (SSH for local dev).
#
# Dry-run cooperation: `aql vault exec --dry-run` injects a fixed filler in
# place of the real token, so the publish can be rehearsed without
# credentials. When the gem or GitHub token is that filler we build the gem
# (validating packaging), then stop — nothing pushed, no tag.
VERSION := $(shell grep -E "\.version\s*=" voxgig_struct.gemspec | sed -E "s/.*[\"']([^\"']+)[\"'].*/\1/")
TAG := ruby/v$(VERSION)
GEM := voxgig_struct-$(VERSION).gem
AQL_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump gemspec version first"; exit 1; fi
	gem build voxgig_struct.gemspec
	@set -e; \
	gemtok="$$GEM_HOST_API_KEY"; ghtok="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$gemtok" = "$(AQL_DRY_RUN_FILLER)" ] || [ "$$ghtok" = "$(AQL_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] aql filler token detected: built $(GEM); nothing pushed, no $(TAG) tag."; \
	  rm -f "$(GEM)"; \
	  exit 0; \
	fi; \
	gem push "$(GEM)"; \
	echo "tag: $(TAG)"; \
	git tag -a "$(TAG)" -m "ruby v$(VERSION)"; \
	if [ -n "$$ghtok" ]; then \
	  echo "push: $(TAG) -> github.com/voxgig/struct (HTTPS, token auth)"; \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$ghtok" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  echo "push: $(TAG) -> origin (ssh)"; \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Published $(GEM) + tag $(TAG)."
