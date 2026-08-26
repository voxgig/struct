.PHONY: inspect build test test-some lint clean reset omni-check

# The boru CLI (https://github.com/boru-lang/boru). Point BORU at a specific
# binary if it is not on PATH:  make test BORU=/path/to/boru
BORU ?= boru

# The corpus runner is voxgig/omni, consumed as a local checkout - it is not
# published, and boru has no registry to publish it to. $OMNI_HOME first,
# then sibling paths, taking the first directory that carries spec/fib.json.
#
# It reaches the suite through `.omni-runner`, a gitignored symlink this
# target points at omni's boru port. A boru import path is a literal with no
# variable to interpolate, so the path has to be fixed; the symlink is what
# makes a per-checkout location fixed. Only `test` depends on it - `build`
# and `lint` never touch the link, so a fresh clone with no omni still
# builds and checks the library (register 4.13).
OMNI_CANDIDATES := $(OMNI_HOME) ../../omni ../../../omni /workspace/omni /home/user/omni
OMNI_DIR := $(firstword $(foreach d,$(OMNI_CANDIDATES),$(if $(wildcard $(d)/spec/fib.json),$(d))))

omni-check:
	@if [ -z "$(OMNI_DIR)" ]; then \
	  echo "struct: voxgig/omni checkout not found - set OMNI_HOME."; \
	  echo "  The tests run on the shared runner; the library itself does not."; \
	  echo "  git clone https://github.com/voxgig/omni ../../omni"; \
	  exit 1; \
	fi
	@ln -sfn "$$(cd $(OMNI_DIR)/boru && pwd)" .omni-runner

inspect:
	@$(BORU) help | head -1

build:
	@echo "No build step for boru (the library is interpreted from source)"

# The corpus runner interprets the library (-no-compile) with static checks
# off (-no-check): the shared build/test corpus is the behavioural contract
# and exercises the port purely at runtime. (The bytecode compiler and the
# static checker each still miscompile/crash on parts of this module — see
# AGENTS.md "Engine caveats".)
test: omni-check
	$(BORU) run -no-check -no-compile test/runner.boru

# One section, or one group, out of a corpus that takes minutes end to end:
#   make test-some GROUP=minor
#   make test-some GROUP=minor.iskey
test-some: omni-check
	$(BORU) run -no-check -no-compile test/runner.boru $(GROUP)

# Lint = the boru static checker over the library (0 errors required;
# advisory warnings pass) plus a load smoke that parses both source files
# and installs the module (every def executes, the export map resolves).
# The module checks clean under a recent boru — see AGENTS.md "Engine
# caveats" for the version note (an older binary crashes / reports phantom
# errors on it).
lint:
	$(BORU) check src/struct.boru
	$(BORU) run -no-check -no-compile test/lint.boru

clean:
	rm -rf .boru

reset: clean
	rm -f .omni-runner
