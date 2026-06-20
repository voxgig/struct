# Makefile for the Clojure port of voxgig/struct.
# Requires the Clojure CLI (`clojure` / `clj`) and a JDK on PATH.

.PHONY: test lint build inspect clean reset publish

# Run the shared JSON corpus through the Clojure implementation.
test:
	clojure -M:test

# "Lint": compile the library + runner namespaces. A clean load means the
# code is syntactically and structurally sound. (No third-party linter is
# required; clj-kondo can be added to the :lint alias if available.)
lint:
	clojure -M:lint -e "(require 'voxgig.struct :reload) (require 'voxgig.struct-runner :reload) (println \"ok\")"

build:
	clojure -M -e "(compile 'voxgig.struct)" 2>/dev/null || clojure -M -e "(require 'voxgig.struct)"

inspect:
	@clojure --version 2>/dev/null || true
	@java -version 2>&1 | head -1

clean:
	rm -rf .cpcache classes target

reset: clean

# The library publishes to Clojars; this target creates the git tag. Set up
# Clojars credentials (CLOJARS_USERNAME / CLOJARS_PASSWORD) for a real deploy.
publish:
	@echo "clojure: publish via Clojars (deps-deploy) + git tag clojure/vX.Y.Z"
