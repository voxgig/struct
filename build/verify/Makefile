# Verification harness: install each port's PUBLISHED package from its
# registry and run a tiny smoke client that proves the artifact installs
# and works. The universal smoke test for every port:
#   getpath({ db: { host: "localhost" } }, "db.host") == "localhost"
#
# Each verify-<port> target INSTALLS the latest published package over the
# network, then runs the smoke client. `make verify` runs them all,
# continues past failures, and prints a pass/fail summary.

PORTS := go typescript javascript python ruby rust

# Ruby toolchain. The published gem requires Ruby >= 2.7; some systems ship
# an older /usr/bin/ruby. Override with `make RUBY=... GEM=... verify-ruby`,
# e.g. RUBY=/opt/homebrew/opt/ruby/bin/ruby GEM=/opt/homebrew/opt/ruby/bin/gem.
RUBY ?= ruby
GEM  ?= gem

.PHONY: verify verify-go verify-typescript verify-javascript \
        verify-python verify-ruby verify-rust clean

verify-go:
	cd go && go get github.com/voxgig/struct/go@latest && go mod tidy && go run .

verify-typescript:
	cd typescript && npm install --silent --no-audit --no-fund && node smoke.cjs

verify-javascript:
	cd javascript && npm install --silent --no-audit --no-fund && node smoke.cjs

verify-ruby:
	cd ruby && $(GEM) install voxgig_struct --no-document --install-dir .gems >/dev/null && GEM_PATH=.gems $(RUBY) smoke.rb

verify-python:
	cd python && uv run --no-project --with voxgig-struct python smoke.py

verify-rust:
	cd rust && cargo run --quiet

verify:
	@pass=""; fail=""; \
	for p in $(PORTS); do \
		echo "=== verify-$$p ==="; \
		if $(MAKE) --no-print-directory verify-$$p; then \
			pass="$$pass $$p"; \
		else \
			fail="$$fail $$p"; \
		fi; \
		echo ""; \
	done; \
	echo "===================="; \
	echo "PASSED:$$pass"; \
	echo "FAILED:$$fail"; \
	echo "===================="; \
	if [ -n "$$fail" ]; then exit 1; fi

clean:
	rm -rf typescript/node_modules typescript/package-lock.json
	rm -rf javascript/node_modules javascript/package-lock.json
	rm -f go/go.sum
	rm -rf ruby/.gems
	rm -rf rust/target
	rm -rf */.venv
	find . -name '__pycache__' -type d -prune -exec rm -rf {} +
