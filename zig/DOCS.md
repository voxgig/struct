# Struct for Zig — Comprehensive Guide

> A **port** of the canonical TypeScript implementation. Behaviour is
> defined by TypeScript and pinned by the shared corpus; this port matches
> it in idiomatic Zig. This guide is the in-depth companion to
> [`README.md`](./README.md) (quick-start + signature reference) and the
> language-neutral [`../DOCS.md`](../DOCS.md).

Four parts, each with a different job:

- **[Tutorial](#1-tutorial)** — build and learn the API hands-on.
- **[How-to guides](#2-how-to-guides)** — recipes for specific tasks.
- **[Reference](#3-reference)** — signatures live in
  [`README.md`](./README.md#function-reference); this section adds the
  Zig-specific semantics and types.
- **[Explanation](#4-explanation--port-specifics)** — the data model, the
  allocator-first convention, and Zig-specific behaviour.

Then: [Build, test, extend](#build-test-and-extend).

> **Read first if you read nothing else:** in this port `allocator` is the
> **first** argument of every function that can allocate, and argument
> order *after* the allocator is a Zig-side choice too — so it is
> `getpath(allocator, path, store)`, **not** the canonical
> `getpath(store, path)`. See [the convention](#allocator-first-and-zig-side-argument-order).

---

## 1. Tutorial

### Build

Zero third-party dependencies — [`build.zig.zon`](./build.zig.zon) declares
`.dependencies = .{}`. The library is the single module
[`src/struct.zig`](./src/struct.zig) plus an in-tree regex engine
([`src/regex.zig`](./src/regex.zig)); nothing is fetched.

```bash
cd zig
zig build test      # build + run the corpus suite
```

Tested with Zig 0.13.0. Import the module by its package name:

```zig
const struct_lib = @import("voxgig-struct");
```

### Your first program

Values live in a custom `JsonValue` union (not `std.json.Value`); maps and
lists are heap-allocated `*MapRef` / `*ListRef` so mutations are visible to
every holder. Build a store, then read a deep path:

```zig
const std = @import("std");
const struct_lib = @import("voxgig-struct");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var root = try struct_lib.JsonValue.makeMap(allocator);
    var db = try struct_lib.JsonValue.makeMap(allocator);
    try db.object.put("host", .{ .string = "db.internal" });
    try db.object.put("port", .{ .integer = 5432 });
    try root.object.put("db", db);

    const path = struct_lib.JsonValue{ .string = "db.host" };
    const val = try struct_lib.getpath(allocator, path, root);
    // val == .{ .string = "db.internal" }
}
```

Note the shape: `getpath(allocator, path, store)`. The path and the store
are both `JsonValue`s; a missing step yields `.null`, never an error.

### Build up the rest of the API

Each call below means the same thing in every port; only the syntax — and
the leading `allocator` — changes. Read
[`../DOCS.md`](../DOCS.md#1-tutorial-a-guided-tour) for the full
language-neutral walkthrough. The Zig-flavoured core:

```zig
const S = struct_lib;

// Merge a chain of maps (later wins; maps deep-merge, lists merge by index).
const merged = try S.merge(allocator, layers, S.MAXDEPTH); // layers: a JsonValue list

// Reshape by example — the spec mirrors the output you want.
const out = try S.transform(allocator, data, spec);

// Validate by example — returns { out, err }; err is non-null on mismatch.
const res = try S.validate(allocator, data, spec);
if (res.err) |msg| std.debug.print("invalid: {s}\n", .{msg});

// Walk the tree — before/after callbacks may replace values.
const w = try S.walk(allocator, tree, null, after_fn, S.MAXDEPTH);

// Select children by query — each match tagged with its $KEY.
const hits = try S.select(allocator, children, query);
```

---

## 2. How-to guides

### Bridge to and from `std.json`

Stay in `JsonValue` everywhere; convert only at the boundary:

```zig
const v = try S.fromStdJson(allocator, std_value);   // parse input
const j = try S.toStdJson(allocator, v);             // hand back to an encoder
```

### Read or set a deep value

`getpath` returns `.null` for a missing path. For a single key with a
default use `getprop`; for "value unless null" use `getdef`. `setpath`
creates intermediate maps and returns the mutated store — and because
containers are `*MapRef`/`*ListRef`, that mutation is visible through every
handle to the store.

```zig
const v = try S.getprop(allocator, node, .{ .string = "timeout" }, .{ .integer = 30 });
const d = S.getdef(maybe, .{ .string = "fallback" }); // no allocator: pure switch
_ = try S.setpath(allocator, store, .{ .string = "service.db.host" }, .{ .string = "x" });
```

`getelem(allocator, list, key, alt)` is list-specific: `-1` indexes from
the end, and a `function`-valued `alt` is **invoked** when the element is
absent (`getprop`/`getdef` do not call `alt`).

### Build literals quickly

```zig
const m = try S.jm(allocator, &.{ .{ .string = "a" }, .{ .integer = 1 } }); // { a: 1 }
const t = try S.jt(allocator, &.{ .{ .integer = 1 }, .{ .bool = true } });  // [1, true]
```

### Serialise

```zig
const compact = try S.jsonify(allocator, value, 0, 0);       // indent 0 = compact
const pretty  = try S.jsonify(allocator, value, 2, 0);       // 2-space indent
const tiny    = try S.jsonifyCompact(allocator, value);      // no whitespace
const log     = try S.stringify(allocator, value, 80);       // truncated human form
```

`jsonify` emits keys in **insertion order** (matching the canonical
`JSON.stringify`); `stringify` emits sorted keys for a stable human form.
Both are pinned by the `minor.jsonify` corpus set.

For `{ a: 1, b: [2, 3] }`, `jsonify` with indent 2 pretty-prints across
lines, while `stringify` gives the quote-light one-liner:

<!-- example: minor/jsonify#brace -->
```zig
var v = try S.JsonValue.makeMap(allocator);
try v.object.put("a", .{ .integer = 1 });
var b = try S.JsonValue.makeList(allocator);
try b.array.append(.{ .integer = 2 });
try b.array.append(.{ .integer = 3 });
try v.object.put("b", b);
const pretty = try S.jsonify(allocator, v, 2, 0);
// pretty == "{\n  \"a\": 1,\n  \"b\": [\n    2,\n    3\n  ]\n}"
```
<!-- => "{\n  \"a\": 1,\n  \"b\": [\n    2,\n    3\n  ]\n}" -->

<!-- example: minor/stringify#brace -->
```zig
const human = try S.stringify(allocator, v, null);   // {a:1,b:[2,3]}
```
<!-- => "{a:1,b:[2,3]}" -->

For more task recipes (`$EACH`, `$MERGE`, `$FORMAT`, `$ONE`, `$EXACT`, …)
see the language-neutral [How-to guides](../DOCS.md#2-how-to-guides) — the
spec syntax is identical; only the host literals and the leading
`allocator` differ.

---

## 3. Reference

The full Zig signatures are in
[`README.md` → Function reference](./README.md#function-reference). The
canonical public surface (the 48 names the parity tool checks) is defined
once in TypeScript; this port exposes them from
[`src/struct.zig`](./src/struct.zig), in lowercase canonical names
(`getpath`, `setpath`, …).

Zig-specific points the signatures don't show:

- **`JsonValue` is a tagged union**, not `std.json.Value`. Scalars are
  by-value (`.null`, `.bool`, `.integer: i64`, `.float: f64`,
  `.string`, `.number_string`); `.object: *MapRef` and `.array: *ListRef`
  are heap pointers so containers are reference-stable. `.function` boxes a
  `*const fn (Allocator) anyerror!JsonValue`.
- **Allocation and errors are explicit.** Anything that may allocate takes
  `Allocator` first and returns `!T`; `getpath` and the inject family
  return `anyerror!JsonValue` because recursion makes the error set open.
- **`validate` returns a value, it does not throw.** Its result is an
  anonymous `struct { out: JsonValue, err: ?[]const u8 }` — check `err`
  rather than catching. (The canonical TS throws; this is the idiomatic
  Zig shape for the same contract.)
- **`getdef`, the predicates, `typify`, `size`, and `typename` are
  allocator-free** — pure functions over `JsonValue`. Everything that
  builds a new value (`keysof`, `items`, `clone`, `slice`, `jsonify`, …)
  takes the allocator.
- **Type flags combine bitwise.** `typify` returns an `i64` bit-field
  (`T_scalar | T_string`, …); `typename(t)` names the dominant bit.
  `typify(.null)` is `T_scalar | T_null`. The flags live at fixed bit
  positions matching TS (`T_any = (1<<31)-1`, `T_node = 1<<6`).
- **`transform` takes `(allocator, data, spec)`** — there is no `extra`
  parameter in the public signature, so `$APPLY` here resolves
  function-typed slots already present in the data/spec rather than a
  separately-registered table.

---

## 4. Explanation & port specifics

### Allocator-first (and Zig-side argument order)

This is the one thing that surprises readers coming from another port.
Idiomatic Zig threads an `Allocator` explicitly through every call that may
allocate, as the **first** parameter, and lets the caller own the
resulting memory. So:

```zig
getpath(allocator, path, store)     // not (store, path)
setpath(allocator, store, path, val)
getprop(allocator, val, key, alt)
```

The order *after* the allocator is also chosen for Zig (e.g. `getprop`
takes `val, key, alt`). The functions still do exactly what the canonical
ones do — only the call shape differs. This is the only port where
post-allocator order does not track the canonical `(store, path, …)`
ordering; the [`README.md`](./README.md#argument-order-note) and
[`../DOCS.md`](../DOCS.md) both call it out. Consequence: the arena/GPA you
pass in owns every returned map, list, and string — most callers use one
arena per request and free it in one shot.

### A custom `JsonValue`, not `std.json.Value`

`std.json.Value` is a value type: assignment copies, and nested mutation is
awkward. The canonical algorithms (`merge`, `walk`, `inject`, `setpath`)
assume **reference-stable** lists and maps — a mutation through one handle
is visible to all. So the port wraps containers in heap-allocated `MapRef`
/ `ListRef` structs, the Zig analogue of the Go/PHP `ListRef`. `MapRef`
uses a `std.StringArrayHashMap`, which preserves **insertion order** — key
order is observable through `keysof`, `items`, and `jsonify`, so an
unordered map would fail the corpus. `fromStdJson`/`toStdJson` bridge at
the boundary.

### `null` versus absent (Group A/B)

Zig has no `undefined` JSON value, so the port models "absent" with the
`.null` case and applies the [Group A/B rule](../design/REPORT.md):

- **Group A readers** (`getprop`, `getelem`, `haskey`, `isempty`,
  `isnode`) treat a stored `.null` as *no value* — you get the `alt` or
  `false`.
- **Group B value-processors** (`setprop`, `clone`, `walk`, `merge`,
  `inject`, `transform`, `validate`, `select`, `jsonify`, …) preserve
  `.null` literally.

This split is the single most common source of port bugs; the
`sentinels.jsonic` corpus category exercises it directly. Full spec:
[`../UNDEF_SPEC.md`](../design/UNDEF_SPEC.md).

### Regex: in-tree engine, and a documented parity gap

The port **ships its own RE2-subset engine** ([`src/regex.zig`](./src/regex.zig),
a Thompson NFA) — no `mvzr`, no third-party crate. The helper module
exposes `re_compile`, `re_test`, and `re_escape`; `re_compile`/`re_test`
use `std.heap.page_allocator` internally so callers need not thread one
through.

**Honest parity gap:** the canonical six-function regex API also defines
`re_find` / `re_find_all` / `re_replace`. The NFA has the primitives, and
wrapper functions exist in [`src/struct.zig`](./src/struct.zig), but those
three are still recorded as a **known parity gap** for Zig in
[`../tools/check_parity.py`](../tools/check_parity.py) (`KNOWN_GAPS["zig"] =
{"refind", "refindall", "rereplace"}`) — treated as accepted, documented
divergence rather than wired-and-verified parity. Treat them as
not-yet-guaranteed until that entry shrinks. Engine-family edges (zero-width
`re_replace` → `"XXbXcX"`, no catastrophic backtracking) are detailed in
[`README.md` → Regex](./README.md#regex) and
[`../REGEX_PATHOLOGICAL.md`](../design/REGEX_PATHOLOGICAL.md).

### This is a port, not the source of truth

A behaviour question is answered by reading the canonical TypeScript and
[`../build/test/`](../build/test/), never by reading this port. If this
port disagrees with the corpus, the port is wrong — fix the port, not the
corpus. Canonical changes start in TypeScript and flow out to every port;
see [`../AGENTS.md`](../AGENTS.md#standard-workflows).

---

## Build, test, and extend

```bash
cd zig
zig build test       # build the library + run the corpus suite
make test            # same, but tolerates the teardown SIGSEGV (see below)
zig build            # compile the library (the compiler is the static analyser)
zig fmt --check src test build.zig    # formatting check
make lint            # wraps `zig fmt --check` (alias: fmt-check)
make inspect         # print Zig + project version
make clean           # rm -rf .zig-cache zig-out
```

The Zig test framework sometimes raises **signal 11 during cleanup** after
all tests pass — `*MapRef`/`*ListRef` cross-references confuse arena
teardown. The [`Makefile`](./Makefile) `test` target filters this: if the
output reports `N/N tests passed` with `N == total`, the run is treated as
successful. `zig build test` runs the suite as 60 `test` blocks, currently
60/60 (see [`../REPORT.md`](../design/REPORT.md)).

Tests live in [`test/`](./test/); the runner
([`test/runner.zig`](./test/runner.zig)) loads the shared corpus from
[`../build/test/`](../build/test/), the same fixtures every port's runner
consumes. There is also an optional walk benchmark (`zig build bench`,
gated on `WALK_BENCH=1`).

**To change behaviour:** behaviour is canonical, so start in
[`../typescript/`](../typescript/), adjust the corpus case in
`../build/test/*.jsonic`, then port the change here, run `zig build test`
until green, and re-run `python3 ../tools/check_parity.py`. The full
checklist is in [`../AGENTS.md`](../AGENTS.md) and the port-specific notes
are in [`AGENTS.md`](./AGENTS.md).
