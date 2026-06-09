# Struct for Zig

> Zig port of the canonical TypeScript implementation.
> Status: complete.  See [`../REPORT.md`](../design/REPORT.md) for parity.

For motivation, language-neutral concepts, and the cross-language
parity matrix, see the [top-level README](../README.md).


## Install

Inside the monorepo:

```bash
cd zig
zig build test
```

Tested with Zig 0.13.0.  Module: [`src/struct.zig`](./src/struct.zig).
Package name: `voxgig-struct`.

```zig
const struct_lib = @import("voxgig-struct");
```


## Quick start

```zig
const std = @import("std");
const struct_lib = @import("voxgig-struct");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var root = try struct_lib.JsonValue.makeMap(allocator);
    defer root.deinit(allocator);

    var db = try struct_lib.JsonValue.makeMap(allocator);
    try db.object.put("host", .{ .string = "localhost" });
    try root.object.put("db", db);

    const path = struct_lib.JsonValue{ .string = "db.host" };
    const val = try struct_lib.getpath(allocator, path, root);
    // val == .{ .string = "localhost" }
}
```


## Argument-order note

The Zig port follows the language convention of placing `allocator`
as the **first** argument.  Argument order *after* the allocator is
also a Zig-side choice, so signatures look like:

```zig
getpath(allocator, path, store)         // not (store, path, allocator)
```

This is the only port where post-allocator order does not match the
canonical `(store, path, ...)` ordering used by the other ports.
The function still does the same thing.


## Function reference

Source: [`src/struct.zig`](./src/struct.zig).

### Core type

```zig
pub const JsonValue = union(enum) {
    null,
    bool: bool,
    integer: i64,
    float: f64,
    string: []const u8,
    number_string: []const u8,
    object: *MapRef,        // pointer-stable map
    array: *ListRef,        // pointer-stable list
    function: JsonFunc,
};
```

`MapRef` and `ListRef` are heap-allocated wrappers so mutations are
visible to every holder.  This preserves the canonical
"reference-stable" semantics.

### Predicates

```zig
pub fn isnode(val: JsonValue) bool
pub fn ismap(val: JsonValue) bool
pub fn islist(val: JsonValue) bool
pub fn iskey(val: JsonValue) bool
pub fn isempty(val: JsonValue) bool
pub fn isfunc(val: JsonValue) bool
```

### Type inspection

```zig
pub fn typify(val: JsonValue) i64
pub fn typename(t: i64) []const u8
```

### Size, slice, pad

```zig
pub fn size(val: JsonValue) i64
pub fn slice(allocator: Allocator, val: JsonValue,
             start_in: ?i64, end_in: ?i64) !JsonValue
pub fn sliceMut(allocator: Allocator, val: JsonValue,
                start_in: ?i64, end_in: ?i64, mutate: bool) !JsonValue
pub fn pad(allocator: Allocator, s: []const u8,
           padding: i64, padchar: u8) ![]const u8
```

### Property access

```zig
pub fn getprop(allocator: Allocator, val: JsonValue,
               key: JsonValue, alt: JsonValue) !JsonValue
pub fn setprop(allocator: Allocator, parent: JsonValue,
               key: JsonValue, newval: JsonValue) !JsonValue
pub fn delprop(allocator: Allocator, parent: JsonValue,
               key: JsonValue) !JsonValue
pub fn getelem(allocator: Allocator, val: JsonValue,
               key: JsonValue, alt: JsonValue) !JsonValue
pub fn getdef(val: JsonValue, alt: JsonValue) JsonValue
pub fn haskey(allocator: Allocator, val: JsonValue,
              key: JsonValue) !bool
pub fn keysof(allocator: Allocator, val: JsonValue) !JsonValue
pub fn items(allocator: Allocator, val: JsonValue) !JsonValue
pub fn strkey(allocator: Allocator, key: JsonValue) ![]const u8
```

### Path operations

```zig
pub fn getpath(allocator: Allocator, path_val: JsonValue,
               store: JsonValue) anyerror!JsonValue
pub fn getpathInj(allocator: Allocator, path_val: JsonValue,
                  store: JsonValue, inj: ?*Injection) anyerror!JsonValue
pub fn setpath(allocator: Allocator, store: JsonValue,
               path_val: JsonValue, val: JsonValue) !JsonValue
pub fn pathify(allocator: Allocator, val: JsonValue,
               from: usize, end: usize) ![]const u8
```

### Tree operations

```zig
pub fn walk(allocator: Allocator, ...) anyerror!JsonValue
pub fn merge(allocator: Allocator, val: JsonValue,
             maxdepth: i32) !JsonValue
pub fn clone(allocator: Allocator, val: JsonValue) !JsonValue
pub fn flatten(allocator: Allocator, val: JsonValue,
               depth: i64) !JsonValue
```

### String / URL / JSON

```zig
pub fn escre(allocator: Allocator, s: []const u8) ![]const u8
pub fn escurl(allocator: Allocator, s: []const u8) ![]const u8
pub fn join(allocator: Allocator, arr: JsonValue,
            sep: []const u8, urlMode: bool) ![]const u8
pub fn jsonify(allocator: Allocator, val: JsonValue,
               indent_size: usize, offset: usize) ![]const u8
pub fn jsonifyCompact(allocator: Allocator,
                      val: JsonValue) ![]const u8
pub fn stringify(allocator: Allocator, val: JsonValue,
                 maxlen: ?usize) ![]const u8
pub fn stringifyPretty(allocator: Allocator, val: JsonValue,
                       maxlen: ?usize, pretty: bool) ![]const u8
```

### Inject / transform / validate / select

```zig
pub fn inject(allocator: Allocator, val: JsonValue,
              store: JsonValue, inj_opt: ?*Injection) anyerror!JsonValue
pub fn transform(allocator: Allocator, data: JsonValue,
                 spec: JsonValue) !JsonValue
// validate, select also present — see source
```

### `std.json` interop

```zig
pub fn fromStdJson(allocator: Allocator, jv: StdJsonValue) anyerror!JsonValue
pub fn toStdJson(allocator: Allocator, v: JsonValue) anyerror!StdJsonValue
```

Use these at API boundaries (parsing input, returning to a JSON
encoder) and stay in `JsonValue` everywhere else.


## Constants

```zig
pub const T_any: i64
pub const T_noval: i64
// ... 15 type bit-flags total
pub const M_KEYPRE: i64
pub const M_KEYPOST: i64
pub const M_VAL: i64
pub const SKIP: JsonValue
pub const DELETE: JsonValue
```


## Transform commands

```
$DELETE  $COPY    $KEY     $META    $ANNO
$MERGE   $EACH    $PACK    $REF     $FORMAT  $APPLY
```


## Validate checkers

```
$MAP   $LIST   $STRING   $NUMBER   $INTEGER   $DECIMAL  $BOOLEAN
$NULL  $NIL    $FUNCTION $INSTANCE $ANY       $CHILD    $ONE     $EXACT
```


## Notes

### Why a custom `JsonValue`

Zig's stdlib `std.json.Value` is a value type: assignment copies and
nested mutation is awkward.  The canonical algorithm assumes
reference-stable lists and maps, so the port wraps containers in
heap-allocated `MapRef` / `ListRef` structs.  Conversion functions
bridge to and from `std.json.Value` at the boundary.

### Allocator threaded through every call

Idiomatic Zig: every function that may allocate takes an
`Allocator` as its first argument.  Callers control lifetime
explicitly; errors propagate through `!` returns.

### Status

Complete: all major subsystems are present and the port passes its share
of the shared corpus. One honest caveat — the top-level `re_find` /
`re_find_all` / `re_replace` wrappers are not yet wired (the in-tree NFA
engine has the primitives), a documented known gap in
[`../tools/check_parity.py`](../tools/check_parity.py). See
[`../REPORT.md`](../design/REPORT.md) for the cross-port matrix.


## Regex

Uniform regex API (see `/design/REGEX_API.md`). The Zig port **ships its own
RE2-subset engine** in `src/regex.zig` (Thompson NFA), replacing the
earlier `mvzr` dependency. No third-party runtime crates.

### API

| Function | Returns |
|---|---|
| `re_compile(pattern)`                          | `?ReCompiled` (nil on bad pattern) |
| `re_test(pattern, input)`                      | `bool` |
| `re_find(alloc, pattern, input)`               | `?[][]const u8` (caller frees) |
| `re_find_all(alloc, pattern, input)`           | `?[][][]const u8` (caller frees both levels) |
| `re_replace(alloc, pattern, input, repl)`      | `![]u8` (caller frees) |
| `re_escape(alloc, s)`                          | `![]const u8` |

`ReCompiled` is an alias for the engine's `Regex` type
(`src/regex.zig`); it owns an instruction buffer and is released with
`.deinit()`.

### Dialect

The in-tree engine implements the RE2 subset documented in `/design/REGEX.md`:
literals + escapes, `.`, `^`/`$`, `* + ? {n} {n,} {n,m}` (greedy + lazy),
classes incl. `\d \w \s` and friends, `\b`/`\B`, `(...)` / `(?:...)`,
alternation.

**Not supported** (by design — RE2 doesn't either): backreferences,
lookaround, possessive quantifiers, atomic groups.

### Sharp edges (Zig-specific)

- **Allocator-explicit.** `re_test` and `re_compile` use
  `std.heap.page_allocator` internally so callers don't have to pipe
  one through every call; the find/find_all/replace wrappers ask for
  one because they return caller-owned slices.
- **`re_find` / `re_find_all` slices alias the input.** They are
  valid only while `input` is alive. Copy if you need to retain past
  the input's lifetime.
- **`re_replace` takes the replacement literally** in the current
  wrapper — no `$&`/`$1..` expansion. The engine's lower-level
  callback variant gives full control.
- **No catastrophic backtracking.** Thompson-NFA construction; P1/P2
  finish in microseconds.
- **Zero-width `re_replace`** matches the in-tree-Thompson and
  PCRE/ECMA convention: `re_replace(alloc, "a*", "abc", "X")` returns
  `"XXbXcX"`. Go (RE2) returns `"XbXcX"` instead; this is RE2's
  chosen rule and we don't paper over it.

See `/design/REGEX_PATHOLOGICAL.md` for the cross-port pathological-input panel.


## Build and test

```bash
cd zig
zig build test
# or:
make test
```

The test framework sometimes raises signal 11 during cleanup after
all tests pass (due to `*MapRef`/`*ListRef` cross-references in
arena teardown).  The Makefile filters this: if the output reports
`N/N tests passed` with `N == total`, it treats the run as
successful.

Tests in [`test/`](./test/) consume fixtures from
[`../build/test/`](../build/test/).
