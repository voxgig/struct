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

# Lint = the aql static checker over the library (0 errors required;
# advisory warnings pass) plus a load smoke that parses both source files
# and installs the module (every def executes, the export map resolves).
# The module checks clean under a recent aql — see AGENTS.md "Engine
# caveats" for the version note (an older binary crashes / reports phantom
# errors on it).
lint:
	$(AQL) check src/struct.aql
	$(AQL) run -no-check -no-compile test/lint.aql

clean:
	rm -rf .aql

reset: clean
