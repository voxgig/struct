# Makefile for the OCaml port of voxgig/struct.
# Requires the OCaml compiler (ocamlc / ocamlopt). No third-party libraries.

OCAMLC = ocamlc
SRC = src/vregex.ml src/voxgig_struct.ml
TESTSRC = $(SRC) test/runner.ml

.PHONY: test bench lint build inspect clean reset publish

# Build and run the shared JSON corpus through the OCaml implementation.
test: run_tests
	./run_tests

run_tests: $(TESTSRC)
	$(OCAMLC) -I src $(TESTSRC) -o run_tests

# Cross-port performance harness (JSON contract; see build/bench/README.md).
# Native (ocamlopt) for representative timings; build log to stderr.
bench:
	@ocamlopt -I src -I +unix unix.cmxa $(SRC) bench/bench.ml -o bench/bench 1>&2
	@./bench/bench

# "Lint": type-check the library (a clean compile means it is sound). No
# third-party linter is required; ocamlformat can be wired into this target.
lint:
	$(OCAMLC) -I src -c $(SRC)
	@echo ok

# Build the dune library (also (re)generates voxgig-struct.opam from dune-project).
build:
	dune build

inspect:
	@$(OCAMLC) -version

clean:
	rm -f src/*.cmi src/*.cmo test/*.cmi test/*.cmo run_tests
	rm -rf _build

reset: clean

# Release: submit to ocaml/opam-repository via a PR (opam publish). opam is NOT
# an instant registry — the PR is reviewed and merged by opam maintainers.
#
# Monorepo note: opam builds a package from its source archive's ROOT, but our
# dune-project lives in ocaml/. The GitHub *tag* archive is the whole repo, so
# it wouldn't build. Instead we build an ocaml-only tarball (dune-project at the
# root), attach it as a GitHub *release asset* on the tag, and point opam at that
# asset. The tag is pushed FIRST (the asset lives on the release); a failed
# opam publish leaves the tag/release in place — just re-run `opam publish`.
# Auth:
#   GITHUB_TOKEN  tag push + `gh release` upload; opam publish also needs a
#                 GitHub token (public_repo) to fork opam-repository + open the
#                 PR — seed ~/.opam/plugins/opam-publish/<github-user>.token.
# Prereq: gh CLI (or GH_TOKEN) + opam initialised with the opam-publish plugin
#   (opam install opam-publish); dune-project version must match VERSION.
VERSION := $(shell cat VERSION)
TAG := ocaml/v$(VERSION)
PKG := voxgig-struct-$(VERSION)
ASSET_URL := https://github.com/voxgig/struct/releases/download/$(TAG)/$(PKG).tar.gz
AQL_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump ocaml/VERSION first"; exit 1; fi
	@dpv=$$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' dune-project | head -1); \
	  [ "$$dpv" = "$(VERSION)" ] || { echo "version mismatch: VERSION=$(VERSION) vs dune-project=$$dpv — bump both"; exit 1; }
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(AQL_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] aql filler token detected: would tag $(TAG), publish a release asset, and open an opam-repository PR; nothing pushed."; \
	  exit 0; \
	fi; \
	dune build; \
	rm -rf .release && mkdir -p ".release/$(PKG)"; \
	cp -r dune-project src voxgig-struct.opam LICENSE README.md ".release/$(PKG)/"; \
	( cd .release && tar czf "$(PKG).tar.gz" "$(PKG)" ); \
	git tag -a "$(TAG)" -m "ocaml v$(VERSION)"; \
	git -c http.extraheader="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$token" | base64 | tr -d '\n')" push https://github.com/voxgig/struct.git "$(TAG)"; \
	GH_TOKEN="$$token" gh release create "$(TAG)" ".release/$(PKG).tar.gz" --title "ocaml v$(VERSION)" --notes "OCaml port of voxgig/struct — opam source archive (dune-project at root)."; \
	opam publish --no-browser "$(ASSET_URL)"; \
	echo "Tagged $(TAG), published release asset, opened opam-repository PR (review pending)."
