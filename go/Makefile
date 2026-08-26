.PHONY: build test bench lint vet fmt fmt-check clean all audit publish

# voxgig/omni comes from its release tag, `go/v0.1.0` - Go requires the
# directory prefix for a module in a subdirectory - so there is no sibling
# checkout to find and no $OMNI_HOME to set. testutil/go.mod names it,
# testutil/go.sum pins it, and the checksum database backs both.
#
# The harness is still a nested module, ./testutil, and that is what keeps
# the dependency off the library: `go build ./...` here skips a nested
# module, so voxgigstruct compiles with no omni whatever, and `go mod tidy`
# in THIS module cannot add voxgig/omni to the published dependency graph.
# The cost is that ./... no longer reaches the harness, so each target
# names it.
#
# The workspace remains, minus omni: the library's own test files import
# ./testutil, and a nested module is invisible to its parent without one.
go.work:
	go work init . ./testutil

build: go.work
	go build ./...

# -count=1 disables the test cache: the corpus is read at run time, so Go
# cannot see that build/test/test.json changed and would report a stale pass.
test: go.work
	go test -count=1 -v ./... ./testutil/...

# Cross-port performance harness (JSON contract; see build/bench/README.md).
bench:
	@go run ./bench

# Code quality: golangci-lint (errcheck/govet/ineffassign/staticcheck/unused),
# plus a gofmt formatting check.
lint: go.work fmt-check vet
	golangci-lint run ./... ./testutil/...

vet: go.work
	go vet ./... ./testutil/...

fmt:
	go fmt ./...

fmt-check:
	@unformatted=$$(gofmt -l .); \
	if [ -n "$$unformatted" ]; then \
		echo "gofmt: the following files are not formatted:"; \
		echo "$$unformatted"; \
		exit 1; \
	fi

clean:
	go clean ./...
	rm -rf go.work go.work.sum

all: fmt vet lint build test

# Supply-chain + security: Go vuln DB (with reachability) + gosec SAST.
# go.work, because both tools load the test module too, and that module
# imports voxgig/omni.
audit: go.work
	govulncheck ./... ./testutil/...
	gosec -quiet ./... ./testutil/...

# Release: Go modules have no registry — publishing IS the git tag. The module
# lives in a subdirectory, so the tag MUST be the `go/vX.Y.Z` submodule form
# for `go get github.com/voxgig/struct/go@vX.Y.Z` to resolve it. Version is in
# the VERSION file (Go has no manifest version field).
#
# Push auth: a headless/CI run (e.g. `boru vault exec --for=github <alias> --
# make publish-go`) injects GH_TOKEN/GITHUB_TOKEN. When a token is present we
# push the tag over HTTPS, carrying the credential in an Authorization header
# (not the remote URL), so it never lands in the URL, in .git/config, or in
# plaintext argv. With no token we fall back to the `origin` remote (SSH for
# local dev). The token is read from the environment and never echoed.
#
# Dry-run cooperation: `boru vault exec --dry-run` injects the fixed filler
# value in place of the real secret, so a full publish command can be
# rehearsed without credentials. When the token is that filler, we run every
# step up to (but not including) tagging/pushing, report what would happen,
# and exit 0 — no tag is created and nothing is pushed.
VERSION := $(shell cat VERSION)
TAG := go/v$(VERSION)
# (The literal keeps the legacy AQL name: it must match the boru vault's dryRunFiller constant.)
BORU_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump go/VERSION first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(BORU_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] boru filler token detected: would tag $(TAG) and push it over"; \
	  echo "[dry-run] HTTPS to github.com/voxgig/struct — no tag created, nothing pushed."; \
	  exit 0; \
	fi; \
	echo "tag: $(TAG)"; \
	git tag -a "$(TAG)" -m "go v$(VERSION)"; \
	if [ -n "$$token" ]; then \
	  echo "push: $(TAG) -> github.com/voxgig/struct (HTTPS, token auth)"; \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$token" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  echo "push: $(TAG) -> origin (ssh)"; \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Published $(TAG). Consumers: go get github.com/voxgig/struct/go@v$(VERSION)"
