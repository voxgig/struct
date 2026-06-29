# Verification harness: install each port's PUBLISHED package from its
# registry and run a tiny smoke client that proves the artifact installs
# and works. The universal smoke test for every port:
#   getpath({ db: { host: "localhost" } }, "db.host") == "localhost"
#
# `make verify` runs the status-aware driver (verify.py): it asks
# tools/release_status.py for LIVE publish status, verifies ONLY the ports
# actually published, retries transient registry/network errors (reporting
# them as UNAVAILABLE, not FAIL), skips unpublished ports, and prints a full
# report. Each verify-<port> below SELF-CLEANS and forces a fresh ONLINE
# install, so we always exercise the live published artifact — never a stale
# local copy or cached resolution.

PORTS := go typescript javascript python ruby rust

# Ruby toolchain. The published gem requires Ruby >= 2.7; some systems ship
# an older /usr/bin/ruby. Override with `make RUBY=... GEM=... verify-ruby`,
# e.g. RUBY=/opt/homebrew/opt/ruby/bin/ruby GEM=/opt/homebrew/opt/ruby/bin/gem.
RUBY   ?= ruby
GEM    ?= gem
PYTHON ?= python3

.PHONY: verify verify-go verify-typescript verify-javascript \
        verify-python verify-ruby verify-rust clean

# Each target removes its own artifacts first, then installs fresh from the
# registry with cache-revalidation flags (--prefer-online / --refresh /
# @latest / fresh --install-dir) so the smoke runs against the LIVE package.

verify-go:
	cd go && rm -f go.sum && go get github.com/voxgig/struct/go@latest && go mod tidy && go run .

verify-typescript:
	cd typescript && rm -rf node_modules package-lock.json && npm install --no-audit --no-fund --prefer-online && node smoke.cjs

verify-javascript:
	cd javascript && rm -rf node_modules package-lock.json && npm install --no-audit --no-fund --prefer-online && node smoke.cjs

verify-ruby:
	cd ruby && rm -rf .gems && $(GEM) install voxgig_struct --no-document --clear-sources --source https://rubygems.org --install-dir .gems >/dev/null && GEM_PATH=.gems $(RUBY) smoke.rb

verify-python:
	cd python && uv run --refresh --no-project --with voxgig-struct python smoke.py

verify-rust:
	cd rust && rm -rf target && cargo update --quiet && cargo run --quiet

# Status-aware driver: determine live status, verify only published, handle
# transient registry downtime, full report.
verify:
	@$(PYTHON) verify.py

clean:
	rm -rf typescript/node_modules typescript/package-lock.json
	rm -rf javascript/node_modules javascript/package-lock.json
	rm -f go/go.sum
	rm -rf ruby/.gems
	rm -rf rust/target
	rm -rf */.venv
	find . -name '__pycache__' -type d -prune -exec rm -rf {} +
