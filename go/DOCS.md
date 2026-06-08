# Struct for Go — Comprehensive Guide

> A faithful **port** of the canonical TypeScript implementation. Behaviour
> is defined there and pinned by the shared corpus; this port reproduces it
> in idiomatic Go. This guide is the in-depth companion to
> [`README.md`](./README.md) (the quick-start + signature reference) and the
> language-neutral [`../DOCS.md`](../DOCS.md).

Four parts, each with a different job:

- **[Tutorial](#1-tutorial)** — install and learn the whole API hands-on.
- **[How-to guides](#2-how-to-guides)** — recipes for specific tasks.
- **[Reference](#3-reference)** — signatures live in
  [`README.md`](./README.md#function-reference); this section adds the exact
  Go semantics and types.
- **[Explanation](#4-explanation--port-specifics)** — the model, the port's
  role, and Go-specific behaviour (especially `ListRef`).

Then: [Build, test, extend](#build-test-and-extend).

---

## 1. Tutorial

### Install

Module path `github.com/voxgig/struct/go`; go directive `1.23`; zero
third-party dependencies (stdlib only).

```bash
go get github.com/voxgig/struct/go
```

```go
import voxgigstruct "github.com/voxgig/struct/go"
```

Working from a clone instead:

```bash
cd go
go build ./...
go test ./...
```

### Your first program

```go
package main

import (
	"fmt"
	voxgigstruct "github.com/voxgig/struct/go"
)

func main() {
	config := voxgigstruct.Merge([]any{
		map[string]any{"db": map[string]any{"host": "localhost", "port": 5432}, "debug": false},
		map[string]any{"db": map[string]any{"host": "db.internal"}, "debug": true},
	})

	fmt.Println(voxgigstruct.GetPath(config, "db.host")) // db.internal
	fmt.Println(voxgigstruct.GetPath(config, "db.port")) // 5432 (survived the deep merge)
}
```

### Build up the rest of the API

Each call below has the same meaning in every port; only the syntax
changes. Read [`../DOCS.md`](../DOCS.md#1-tutorial-a-guided-tour) for the
full language-neutral walkthrough; the Go-flavoured version:

```go
// Reshape by example — the spec mirrors the output you want.
out, _ := voxgigstruct.Transform(
	map[string]any{"user": map[string]any{"first": "Ada", "last": "Lovelace"}, "age": 36},
	map[string]any{"name": "`user.first`", "surname": "`user.last`", "years": "`age`"},
)
// map[name:Ada surname:Lovelace years:36]

// Validate by example — leaves are type checkers; returns (data, error).
_, err := voxgigstruct.Validate(
	map[string]any{"name": "Ada", "age": 36},
	map[string]any{"name": "`$STRING`", "age": "`$INTEGER`"},
)

// Walk the tree — replace values on ascent. The key is *string (nil at the root).
voxgigstruct.Walk(tree, nil, func(key *string, val, parent any, path []string) any {
	if val == nil {
		return "DEFAULT"
	}
	return val
})

// Select children by query — each match tagged with its $KEY.
voxgigstruct.Select(
	map[string]any{"a": map[string]any{"age": 30}, "b": map[string]any{"age": 25}},
	map[string]any{"age": 30},
)
// [map[$KEY:a age:30]]
```

---

## 2. How-to guides

### Read a deep value, with a fallback
```go
voxgigstruct.GetPath(store, "a.b.c")              // nil if missing — never panics
voxgigstruct.GetProp(node, "c", "fallback")       // fallback if the single key is absent
voxgigstruct.GetDef(maybeNil, "fallback")          // fallback only when the value is nil
```
`GetProp` takes the alternate via the variadic `alts ...any`; integer steps
in a path index into lists, and a missing key is `nil`, not an error.

### Collect all validation errors instead of failing fast
`Validate` returns `(any, error)` and stops at the first mismatch. To gather
every error, use `TransformCollect` / the collecting validate variant, or
inspect the returned `error` (it carries the first mismatch message, or an
aggregate when the underlying call collected errors). See
[`README.md` → Notes](./README.md#notes).

### Write a custom transform function (`$APPLY`)
Register a named function and reference it by name in the spec. A custom
function may return the `SKIP` / `DELETE` sentinels to omit/remove the
current key. The exact callable shape is the port-local `Modify` /
`Injector` type — see [`README.md`](./README.md#injection-helpers) and
[`../NOTES.md`](../NOTES.md), since function-value signatures vary by port
and are covered by port-local unit tests, not the JSON corpus.

### Keep a `walk` path past the callback
```go
seen := [][]string{}
voxgigstruct.Walk(tree, func(key *string, val, parent any, path []string) any {
	cp := append([]string(nil), path...) // the path slice is reused — copy to retain it
	seen = append(seen, cp)
	return val
})
```

### Serialise deterministically
```go
voxgigstruct.Jsonify(value)                                  // compact, insertion-ordered keys
voxgigstruct.Jsonify(value, map[string]any{"indent": 2})     // pretty (flags map carries the indent)
voxgigstruct.Stringify(value, 80)                            // truncated human form, for logs
```

For more task recipes (merge configs, rename fields, `$EACH`, `$MERGE`,
`$FORMAT`, `$ONE`, `$EXACT`, …) see the language-neutral
[How-to guides](../DOCS.md#2-how-to-guides) — the spec syntax is identical;
only the host literals differ (`map[string]any{...}`, `[]any{...}`).

---

## 3. Reference

The full Go signatures, with examples for every function, are in
[`README.md` → Function reference](./README.md#function-reference). The
canonical public surface is defined by the `export { … }` block in the
[canonical TS source](../typescript/src/StructUtility.ts); that block *is*
the definition [`../tools/check_parity.py`](../tools/check_parity.py) checks
this port against (case/underscore-insensitively, so `GetPath` matches
`getpath`).

Go-specific points the signatures don't show:

- **`any` at the boundaries.** The data model is JSON-shaped `any`: maps are
  `map[string]any`, lists are `[]any`, and `nil` is the only empty value (see
  below). `IsMap`/`IsList`/`IsNode` classify at runtime.
- **PascalCase names.** Exported identifiers are uppercased: `GetPath`,
  `SetPath`, `Merge`, `EscRe`, `KeysOf`. The README has the full mapping.
- **Variants instead of optional parameters.** Go has no optional or named
  parameters, so where canonical TS takes options the port either collects
  them in a variadic (`Pad(str, args ...any)`, `GetProp(val, key, alts ...any)`)
  or exposes a separate function. `Walk(val, apply, opts...)` is the short
  form, and its `opts` carry the optional `after` callback and `maxdepth`
  (`Walk(val, before, after, maxdepth)`); `WalkDescend` is a separate entry
  point for an ad-hoc recursive descent from a non-root position (it takes an
  explicit `key`, `parent`, and starting `path`). `CloneFlags` is
  clone-with-options; `ItemsApply` is the map-each form of `Items`.
- **`Walk` callback shape.** `WalkApply` is
  `func(key *string, val any, parent any, path []string) any`. The key is a
  `*string` — `nil` at the root, otherwise the map key or the string form of
  a list index.
- **`(any, error)` for fallible calls.** `Transform`, `Validate`, and their
  variants return `(any, error)` per Go idiom; the error carries the first
  mismatch message (or an aggregate).
- **Type flags** combine bitwise: `Typify("hi")` is `T_scalar | T_string`;
  test with `0 < (T_string & t)`. `Typify(nil)` is `T_scalar | T_null`.

---

## 4. Explanation & port specifics

### This port's role

TypeScript is the source of truth. The shared corpus in
[`../build/test/`](../build/test/) is generated to match the canonical code,
and this port is held to that corpus. A behaviour question is answered by
reading the canonical TS, not by polling the ports; a change to canonical
behaviour starts there, then flows to the corpus and out to every port (see
[`../AGENTS.md`](../AGENTS.md#standard-workflows)).

### `nil` covers absent *and* JSON null

Go has only `nil`. Both "absent" and the JSON `null` scalar map to `nil` at
the user-facing API. The port already follows the **Group A** rule (see
[`../UNDEF_SPEC.md`](../UNDEF_SPEC.md) and [`../REPORT.md`](../REPORT.md)):
readers (`GetProp`, `GetElem`, `HasKey`, `IsEmpty`, `IsNode`) treat a stored
`null` as "no value" and return the alt / `false`, while value-processors
(`SetProp`, `Clone`, `Walk`, `Merge`, `Inject`, `Transform`, `Validate`,
`Select`) preserve it literally. Where the corpus must distinguish the two,
the test runner uses the string sentinels `__NULL__` (a real JSON null),
`__UNDEF__` (absent), and `__EXISTS__` (present).

### `ListRef` — reference-stable lists (the thing to understand)

The canonical engine relies on JavaScript arrays being **mutable and shared
by reference**: `walk`, `merge`, `setpath`, and `inject` mutate a list
through one handle and expect every other holder to see the change. Go
slices don't give you that — a slice is a value, and `append` may reallocate
the backing array, so a mutation through one copy is invisible to another.

To restore the canonical assumption, the port wraps lists in a thin generic
type:

```go
type ListRef[T any] struct {
	List []T
}
```

Every holder keeps a `*ListRef[T]` (a *pointer*), so a mutation to `.List`
is visible to all aliases — exactly the JS array semantics the algorithms
need. Construct one directly or with the helper, and grow it with `Append` /
`Prepend`:

```go
ref := &voxgigstruct.ListRef[any]{List: []any{1, 2, 3}}
ref2 := voxgigstruct.ListRefCreate[any]() // empty *ListRef[any]
ref.Append(4)                              // ref.List == []any{1, 2, 3, 4}
```

This is mostly internal: `Injection` carries `*ListRef[string]` for keys and
path and `*ListRef[any]` for the node stack and error collector, and
`Merge`/`Inject` wrap bare `[]any` on the way in and unwrap back to plain
`[]any` on the way out (so what you pass in and get back is ordinary
JSON-shaped data). You only meet `ListRef` directly when writing a custom
modify/`$APPLY` callback that mutates a list and needs that mutation to
stick across the recursion. If you hold a value that might be a wrapped
list, type-assert `*ListRef[any]` and read its `.List`.

### Regex

The uniform six-function regex API (`ReCompile` / `ReTest` / `ReFind` /
`ReFindAll` / `ReReplace` / `ReReplaceFunc`, plus `ReEscape` as an alias for
`EscRe`) wraps Go's stdlib `regexp` package, which **is** the RE2 reference
implementation: linear-time matching, no backtracking, and therefore no
backreferences or lookaround (RE2 rejects them at compile time — there is no
PCRE escape hatch). Stay inside the **RE2 subset** documented in
[`../REGEX.md`](../REGEX.md); `ReCompile` is a pass-through to
`regexp.MustCompile`, so an invalid pattern **panics** (wrap in `recover()`
if you accept user-supplied patterns).

One documented divergence: **zero-width `re_replace`**.
`ReReplace("a*", "abc", "X")` returns `"XbXcX"` because RE2 suppresses an
empty match immediately after a non-empty match at the same offset; the
ECMA / PCRE / backtracking ports (and the in-tree Thompson engines) return
`"XXbXcX"` instead. This is inherent to Go's host engine and is **not**
papered over — portable callers should not depend on cross-port identity of
zero-width replacement output. Full panel:
[`../REGEX_PATHOLOGICAL.md`](../REGEX_PATHOLOGICAL.md).

---

## Build, test, and extend

```bash
cd go
go build ./...                  # compile the library
go test ./...                   # run the shared corpus suite
golangci-lint run ./...         # static analysis (errcheck/govet/staticcheck/…)
go vet ./...                    # vet pass
make lint                       # gofmt check + go vet + golangci-lint
make test                       # go test -v ./...
```

The runner in [`voxgigstruct_test.go`](./voxgigstruct_test.go) loads the
shared corpus from [`../build/test/`](../build/test/) and mirrors the
reference runner. This port passes 92/92 of the shared corpus suite (see
[`../REPORT.md`](../REPORT.md)).

**To change behaviour:** behaviour is canonical, so start in the TypeScript
source and the corpus, not here — edit
[`../typescript/src/StructUtility.ts`](../typescript/src/StructUtility.ts),
adjust the corpus case in `../build/test/*.jsonic`, then port the same logic
here, run `go test ./...` until green, and re-run
[`../tools/check_parity.py`](../tools/check_parity.py) plus every other
port's tests. The full checklist is in [`../AGENTS.md`](../AGENTS.md).
