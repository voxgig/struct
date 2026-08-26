# AGENTS.md — Go port

Port-specific notes for AI agents. **Read the repo-wide
[`../AGENTS.md`](../AGENTS.md) first** — it holds the rules that matter most
(canonical-first, corpus-is-contract, parity, zero-deps). This file covers
only what is specific to the Go port.

> **This is a port, not the canonical.** Behaviour is defined by the
> TypeScript source and pinned by the shared corpus
> ([`../build/test/`](../build/test/)). If this port disagrees with the
> corpus, the port is wrong — fix the port, never the corpus.

## Layout

```
go/
├── voxgigstruct.go              # the port: all exported functions + ListRef
├── voxgigstruct_test.go         # corpus-driven tests (loads ../build/test/)
├── regex_pathological_test.go   # regex edge-case panel
├── client_test.go               # example/usage test
├── walk_bench_test.go           # walk benchmark
├── testutil/                    # the test harness — its own module
│   ├── omni.go                  #   voxgig/omni's struct shim, re-exported
│   ├── sdkapi.go                #   the SDK shapes the harness builds
│   ├── sdk.go, direct.go        #   the test client
│   ├── helpers.go               #   NULL/UNDEF/EXISTS markers + Fdt
│   └── go.mod                   #   module .../go/testutil; requires omni
├── go.mod                       # module github.com/voxgig/struct/go; go 1.23
└── Makefile                     # build / test / lint / vet / fmt / audit
```

Package `voxgigstruct`; module path `github.com/voxgig/struct/go`; go
directive 1.23; zero third-party runtime dependencies (stdlib only).

### Two modules, deliberately

The corpus runner is [voxgig/omni](https://github.com/voxgig/omni), taken
from its release tag: `testutil/go.mod` requires
`github.com/voxgig/omni/go v0.1.0` and `testutil/go.sum` pins it with
checksum-database-backed hashes. Go needs the directory prefix for a module
in a subdirectory, so the tag is `go/v0.1.0` and the version Go records is
`v0.1.0`. There is no sibling checkout to find and no `$OMNI_HOME` to set.

What keeps omni out of the *library* is mechanism, not absence — the proxy
serves it, which is exactly why absence was never a guard here. `testutil`
is a **nested module**: `go build ./...` in this module skips it, so the
library compiles with no omni whatever, and `go mod tidy` here cannot write
omni into the published dependency graph. That is unchanged by the move to a
tag, and `tools/omni_isolation.py` asserts it as a declaration check.

The trade is that `./...` no longer reaches the harness. Every Makefile
target names it explicitly (`./... ./testutil/...`); do the same for any
new one, or it will silently stop covering the tests.

`make` still writes a gitignored `go.work`, but over **two** modules — this
one and `./testutil` — and it no longer names omni. It exists only because
the library's own test files import `./testutil`, and a nested module is
invisible to its parent without a workspace. Do not add omni back to it: a
`use` directive makes that module a root module for the build, which shadows
the `v0.1.0` requirement and silently returns the tests to a floating
checkout.

## Commands

```bash
go build ./...                     # compile the library — no omni needed
make test                          # go test -count=1 -v ./... ./testutil/...
make lint                          # fmt-check + go vet + golangci-lint
make audit                         # govulncheck + gosec
```

Prefer the `make` targets over bare `go` commands for anything touching
tests: they generate `go.work` first, and they name `./testutil/...`. A bare
`go test ./...` silently runs the corpus but skips the harness's own tests,
and a bare `go vet ./...` fails outright with no workspace.

`make` also exposes `build`, `fmt`, `fmt-check`, `clean`, and `all`.

## Conventions specific to this port

- **Casing:** PascalCase exported names (`GetPath`, `SetPath`, `Merge`,
  `EscRe`, `KeysOf`). Parity is checked case/underscore-insensitively, so
  `GetPath` satisfies canonical `getpath`.
- **JSON-shaped `any`.** Maps are `map[string]any`, lists are `[]any`. Don't
  introduce concrete structs for data — ports can't follow non-JSON types
  and the corpus is the contract.
- **Variants for optional params.** Go has no optional/named parameters;
  options are collected in a variadic (`Pad`, `GetProp`, `Slice`, `Walk`) or
  split into a separate function (`WalkDescend`, `CloneFlags`,
  `TransformModify`, `TransformCollect`, `ItemsApply`). Keep this pattern;
  don't collapse variants.
- **`(any, error)` for fallible calls.** `Transform`/`Validate` and variants
  return `(any, error)` per Go idiom.

## Gotchas

- **`ListRef[T]` is load-bearing.** Go slices are values (`append` may
  reallocate), so `walk`/`merge`/`setpath`/`inject` would lose mutations
  through aliased slices. The port wraps lists in `type ListRef[T any] struct
  { List []T }` so every holder shares a pointer-stable list. The field is
  `.List` (not `Data`); grow with `Append`/`Prepend`; build with
  `ListRefCreate[T]()` or a literal. Don't "simplify" these to bare `[]any` —
  it breaks reference stability.
- **`nil` is absent *and* JSON null.** Go has only `nil`. The port follows
  the Group A/B rule (already Group A — see
  [`../UNDEF_SPEC.md`](../design/UNDEF_SPEC.md)). Re-read it before touching any
  read/merge/clone path — the top source of port bugs.
- **Corpus markers.** `testutil/runner.go` defines `NULLMARK = "__NULL__"`,
  `UNDEFMARK = "__UNDEF__"`, `EXISTSMARK = "__EXISTS__"`. `__UNDEFMARK__` is
  not a marker value — it's a stale string in older docs.
- **Regex is RE2.** Go's `regexp` *is* RE2: linear-time, no backreferences or
  lookaround, no PCRE escape hatch. `ReCompile` is `regexp.MustCompile`, so a
  bad/out-of-subset pattern **panics**. Zero-width `re_replace` diverges by
  design — `ReReplace("a*", "abc", "X")` returns `"XbXcX"`, not `"XXbXcX"`;
  don't "fix" it (see [`../REGEX_PATHOLOGICAL.md`](../design/REGEX_PATHOLOGICAL.md)).
- **Editing here doesn't change canonical behaviour.** A genuine behaviour
  change starts in the TypeScript source + corpus, then propagates here; run
  `python3 ../tools/check_parity.py` and the touched ports' tests after.

## See also

- Port guide: [`DOCS.md`](./DOCS.md) · Reference + quick start:
  [`README.md`](./README.md)
- Repo rules & workflows: [`../AGENTS.md`](../AGENTS.md)
- The contract: [`../build/test/`](../build/test/) · Parity:
  [`../tools/check_parity.py`](../tools/check_parity.py)
- Null semantics: [`../UNDEF_SPEC.md`](../design/UNDEF_SPEC.md) · Parity matrix:
  [`../REPORT.md`](../design/REPORT.md)
