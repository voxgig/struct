# Struct for Zig

> Zig port of the canonical TypeScript implementation.

For the language-neutral overview, motivation, and concepts, see the
[top-level README](../README.md).

These docs follow the [Diataxis](https://diataxis.fr/) framework.


## Tutorial: your first lookup

### Install

Inside the monorepo:

```bash
cd zig
zig build test
```

The package is `voxgig-struct`; the module is in
[`src/struct.zig`](./src/struct.zig).

### A first path lookup

```zig
const std = @import("std");
const struct_lib = @import("struct");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Build a JsonValue tree.
    var root = try struct_lib.JsonValue.makeMap(allocator);
    defer root.deinit(allocator);

    var db = try struct_lib.JsonValue.makeMap(allocator);
    try db.object.put("host", .{ .string = "localhost" });
    try root.object.put("db", db);

    const path = struct_lib.JsonValue{ .string = "db.host" };
    const val = try struct_lib.getpath(allocator, root, path);
    // val == .{ .string = "localhost" }
}
```


## How-to recipes

### Read a deep value safely

```zig
const v = try struct_lib.getpath(allocator, store, path_val);
const v = try struct_lib.getprop(allocator, store, key_val, alt_val);
```

### Set a deep value

```zig
_ = try struct_lib.setpath(allocator, store, path_val, new_val);
```

### Merge

```zig
const merged = try struct_lib.merge(allocator, list_of_maps, maxdepth);
```

### Walk

```zig
_ = try struct_lib.walk(
    allocator,
    tree,
    apply_fn,         // *const fn(...) anyerror!JsonValue
    .{ .before = null, .after = null, .maxdepth = 32 },
);
```

### Transform

```zig
const out = try struct_lib.transform(allocator, data, spec);
```

### Bridging to/from `std.json`

```zig
const v = try struct_lib.fromStdJson(allocator, std_json_value);
const j = try struct_lib.toStdJson(allocator, v);
```


## Reference

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

`MapRef` and `ListRef` are heap-allocated wrappers so that mutations
are visible to every holder.  This preserves the canonical
"reference-stable" semantics.

### Major functions

```zig
pub fn walk(allocator, node, apply, opts) anyerror!JsonValue
pub fn merge(allocator, list, maxdepth) anyerror!JsonValue
pub fn getpath(allocator, store, path) anyerror!JsonValue
pub fn setpath(allocator, store, path, val) anyerror!JsonValue
pub fn injectVal(allocator, val, store, inj_opt) anyerror!JsonValue
pub fn transform(allocator, data, spec) anyerror!JsonValue
```

Predicates and minor utilities follow the canonical naming
(lowercase): `isnode`, `ismap`, `islist`, `iskey`, `isempty`,
`isfunc`, `getprop`, `setprop`, `keysof`, `haskey`, `items`,
`stringify`, `jsonify`, etc.

### `std.json` interop

```zig
pub fn fromStdJson(allocator, jv: StdJsonValue) anyerror!JsonValue
pub fn toStdJson(allocator, v: JsonValue) anyerror!StdJsonValue
```

Use these at API boundaries (parsing input, returning to a JSON
encoder) and stay in `JsonValue` everywhere else.


## Explanation

### Why a custom `JsonValue` rather than `std.json.Value`

Zig's stdlib `std.json.Value` is a value type: assignment copies and
nested mutation is awkward.  The canonical algorithm assumes
reference-stable lists and maps, so the port wraps containers in
heap-allocated `MapRef` / `ListRef` structs.  Conversion functions
bridge to and from `std.json.Value` at the boundary.

### Allocator threaded through every call

Idiomatic Zig: every function that may allocate takes an
`Allocator`.  Callers control lifetime explicitly.  Errors propagate
through `!` returns.

### Status

In progress.  Coverage of the canonical API is broad (all major
subsystems present) but the test corpus pass rate is being raised.
See [`../REPORT.md`](../REPORT.md) for the latest status.


## Build and test

```bash
cd zig
zig build test
```

Tests in [`test/`](./test/) consume fixtures from
[`../build/test/`](../build/test/).
