# Makefile for the OCaml port of voxgig/struct.
# Requires the OCaml compiler (ocamlc / ocamlopt). No third-party libraries.

OCAMLC = ocamlc
SRC = src/vregex.ml src/voxgig_struct.ml
TESTSRC = $(SRC) test/runner.ml

.PHONY: test lint build inspect clean reset publish

# Build and run the shared JSON corpus through the OCaml implementation.
test: run_tests
	./run_tests

run_tests: $(TESTSRC)
	$(OCAMLC) -I src $(TESTSRC) -o run_tests

# "Lint": type-check the library (a clean compile means it is sound). No
# third-party linter is required; ocamlformat can be wired into this target.
lint:
	$(OCAMLC) -I src -c $(SRC)
	@echo ok

build:
	$(OCAMLC) -I src -c $(SRC)

inspect:
	@$(OCAMLC) -version

clean:
	rm -f src/*.cmi src/*.cmo test/*.cmi test/*.cmo run_tests

reset: clean

# The library publishes to opam; this target creates the git tag. Configure
# opam-publish for a real release.
publish:
	@echo "ocaml: publish via opam + git tag ocaml/vX.Y.Z"
