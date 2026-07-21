.PHONY: inspect build test lint clean reset

# The aql CLI (https://github.com/aql-lang/aql). Point AQL at a specific
# binary if it is not on PATH:  make test AQL=/path/to/aql
AQL ?= aql

inspect:
	@$(AQL) help | head -1

build:
	@echo "No build step for AQL (the library is interpreted from source)"

# The corpus runner interprets the library (-no-compile) with static checks
# off (-no-check): the shared build/test corpus is the behavioural contract
# and exercises the port purely at runtime. (The bytecode compiler and the
# static checker each still miscompile/crash on parts of this module — see
# AGENTS.md "Engine caveats".)
test:
	$(AQL) run -no-check -no-compile test/runner.aql

# Lint = a load smoke: parse both source files and install the module
# (every def executes, the export map resolves). A clean load is the
# strongest static gate the aql toolchain offers this module today
# (see AGENTS.md "Engine caveats" for why `aql check` is not used).
lint:
	$(AQL) run -no-check -no-compile test/lint.aql

clean:
	rm -rf .aql

reset: clean
