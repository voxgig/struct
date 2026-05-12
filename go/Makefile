.PHONY: build test lint vet fmt fmt-check clean all audit

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
