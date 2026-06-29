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

# Release: opam registry upload is a documented manual step for now; this
# target cuts the ocaml/vX.Y.Z git tag headlessly.
# Headless: `aql vault exec --for=github <alias> -- make publish-ocaml` injects
# GH_TOKEN/GITHUB_TOKEN; the tag is pushed over HTTPS via an Authorization header
# (kept out of the URL, .git/config, and argv), else the origin SSH remote.
# `aql vault exec --dry-run` injects a filler we detect to rehearse (no tag).
# set -e: a failed push never leaves a tag behind.
VERSION := $(shell cat VERSION)
TAG := ocaml/v$(VERSION)
AQL_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump ocaml/VERSION first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(AQL_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] aql filler token detected: would tag $(TAG) and push it over"; \
	  echo "[dry-run] HTTPS to github.com/voxgig/struct — no tag created, nothing pushed."; \
	  exit 0; \
	fi; \
	echo "tag: $(TAG)"; \
	git tag -a "$(TAG)" -m "ocaml v$(VERSION)"; \
	if [ -n "$$token" ]; then \
	  echo "push: $(TAG) -> github.com/voxgig/struct (HTTPS, token auth)"; \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$token" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  echo "push: $(TAG) -> origin (ssh)"; \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Tagged $(TAG). opam upload (manual): opam publish"
