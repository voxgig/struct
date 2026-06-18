.PHONY: build test lint vet fmt fmt-check clean all audit publish

build:
	go build ./...

test:
	go test -v ./...

# Code quality: golangci-lint (errcheck/govet/ineffassign/staticcheck/unused),
# plus a gofmt formatting check.
lint: fmt-check vet
	golangci-lint run ./...

vet:
	go vet ./...

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

all: fmt vet lint build test

# Supply-chain + security: Go vuln DB (with reachability) + gosec SAST.
audit:
	govulncheck ./...
	gosec -quiet ./...

# Release: Go modules have no registry — publishing IS the git tag. The module
# lives in a subdirectory, so the tag MUST be the `go/vX.Y.Z` submodule form
# for `go get github.com/voxgig/struct/go@vX.Y.Z` to resolve it. Version is in
# the VERSION file (Go has no manifest version field).
#
# Push auth: a headless/CI run (e.g. `aql vault exec --for=github <alias> --
# make publish-go`) injects GH_TOKEN/GITHUB_TOKEN. When a token is present we
# push the tag over HTTPS, carrying the credential in an Authorization header
# (not the remote URL), so it never lands in the URL, in .git/config, or in
# plaintext argv. With no token we fall back to the `origin` remote (SSH for
# local dev). The token is read from the environment and never echoed.
#
# Dry-run cooperation: `aql vault exec --dry-run` injects the fixed filler
# value in place of the real secret, so a full publish command can be
# rehearsed without credentials. When the token is that filler, we run every
# step up to (but not including) tagging/pushing, report what would happen,
# and exit 0 — no tag is created and nothing is pushed.
VERSION := $(shell cat VERSION)
TAG := go/v$(VERSION)
AQL_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump go/VERSION first"; exit 1; fi
	@token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(AQL_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] aql filler token detected: would tag $(TAG) and push it over"; \
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
