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
VERSION := $(shell cat VERSION)
publish: test
	@if git rev-parse -q --verify "refs/tags/go/v$(VERSION)" >/dev/null; then \
	  echo "tag go/v$(VERSION) already exists — bump go/VERSION first"; exit 1; fi
	git tag -a "go/v$(VERSION)" -m "go v$(VERSION)"
	git push origin "go/v$(VERSION)"
	@echo "Published go/v$(VERSION). Consumers: go get github.com/voxgig/struct/go@v$(VERSION)"
