// Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.

// Voxgig Struct
// =============
//
// Utility functions to manipulate in-memory JSON-like data structures.
// Zig port from the canonical TypeScript implementation.

const std = @import("std");
const Allocator = std.mem.Allocator;

// Keep std.json types for parsing at the boundary.
pub const StdJsonValue = std.json.Value;

// ============================================================================
// MapRef / ListRef — heap-allocated wrappers for pointer-stable mutations.
// All holders of the same *MapRef / *ListRef see mutations.
// ============================================================================

pub const MapData = std.StringArrayHashMap(JsonValue);
pub const ListData = std.ArrayList(JsonValue);

pub const MapRef = struct {
    data: MapData,

    pub fn get(self: *const MapRef, key: []const u8) ?JsonValue {
        return self.data.get(key);
    }

    pub fn put(self: *MapRef, key: []const u8, val: JsonValue) !void {
        try self.data.put(key, val);
    }

    pub fn count(self: *const MapRef) usize {
        return @intCast(self.data.count());
    }

    pub fn iterator(self: *const MapRef) MapData.Iterator {
        return self.data.iterator();
    }

    pub fn fetchOrderedRemove(self: *MapRef, key: []const u8) ?MapData.KV {
        return self.data.fetchOrderedRemove(key);
    }
};

pub const ListRef = struct {
    data: ListData,

    pub fn append(self: *ListRef, val: JsonValue) !void {
        try self.data.append(val);
    }

    pub fn orderedRemove(self: *ListRef, idx: usize) JsonValue {
        return self.data.orderedRemove(idx);
    }

    pub fn insert(self: *ListRef, idx: usize, val: JsonValue) !void {
        try self.data.insert(idx, val);
    }
};

// Function signature for values stored in the JSON tree.
pub const JsonFunc = *const fn (allocator: Allocator) anyerror!JsonValue;

// Custom value type with pointer-stable containers.
pub const JsonValue = union(enum) {
    null,
    bool: bool,
    integer: i64,
    float: f64,
    string: []const u8,
    number_string: []const u8,
    object: *MapRef,
    array: *ListRef,
    function: JsonFunc,

    pub fn makeMap(allocator: Allocator) !JsonValue {
        const mr = try allocator.create(MapRef);
        mr.* = .{ .data = MapData.init(allocator) };
        return JsonValue{ .object = mr };
    }

    pub fn makeList(allocator: Allocator) !JsonValue {
        const lr = try allocator.create(ListRef);
        lr.* = .{ .data = ListData.init(allocator) };
        return JsonValue{ .array = lr };
    }
};

// Convert from std.json.Value to our pointer-stable JsonValue.
pub fn fromStdJson(allocator: Allocator, jv: StdJsonValue) anyerror!JsonValue {
    return switch (jv) {
        .null => JsonValue{ .null = {} },
        .bool => |b| JsonValue{ .bool = b },
        .integer => |i| JsonValue{ .integer = i },
        .float => |f| JsonValue{ .float = f },
        .string => |s| JsonValue{ .string = s },
        .number_string => |s| JsonValue{ .number_string = s },
        .object => |obj| {
            const mr = try allocator.create(MapRef);
            mr.* = .{ .data = MapData.init(allocator) };
            var it = obj.iterator();
            while (it.next()) |kv| {
                try mr.data.put(kv.key_ptr.*, try fromStdJson(allocator, kv.value_ptr.*));
            }
            return JsonValue{ .object = mr };
        },
        .array => |arr| {
            const lr = try allocator.create(ListRef);
            lr.* = .{ .data = ListData.init(allocator) };
            for (arr.items) |item| {
                try lr.data.append(try fromStdJson(allocator, item));
            }
            return JsonValue{ .array = lr };
        },
    };
}

// Convert from our JsonValue back to std.json.Value.
pub fn toStdJson(allocator: Allocator, v: JsonValue) anyerror!StdJsonValue {
    return switch (v) {
        .null => StdJsonValue{ .null = {} },
        .bool => |b| StdJsonValue{ .bool = b },
        .integer => |i| StdJsonValue{ .integer = i },
        .float => |f| StdJsonValue{ .float = f },
        .string => |s| StdJsonValue{ .string = s },
        .number_string => |s| StdJsonValue{ .number_string = s },
        .object => |mr| {
            var obj = std.json.ObjectMap.init(allocator);
            var it = mr.data.iterator();
            while (it.next()) |kv| {
                try obj.put(kv.key_ptr.*, try toStdJson(allocator, kv.value_ptr.*));
            }
            return StdJsonValue{ .object = obj };
        },
        .array => |lr| {
            var arr = std.json.Array.init(allocator);
            for (lr.data.items) |item| {
                try arr.append(try toStdJson(allocator, item));
            }
            return StdJsonValue{ .array = arr };
        },
        .function => StdJsonValue{ .null = {} },
    };
}

// Mode value for inject step (bitfield).
pub const M_KEYPRE: i32 = 1;
pub const M_KEYPOST: i32 = 2;
pub const M_VAL: i32 = 4;

// Special strings.
pub const S_BKEY = "`$KEY`";
pub const S_BANNO = "`$ANNO`";
pub const S_BEXACT = "`$EXACT`";
pub const S_BOPEN = "`$OPEN`";
pub const S_BVAL = "`$VAL`";

pub const S_DKEY = "$KEY";
pub const S_DTOP = "$TOP";
pub const S_DERRS = "$ERRS";
pub const S_DSPEC = "$SPEC";

// General strings.
pub const S_list = "list";
pub const S_base = "base";
pub const S_boolean = "boolean";
pub const S_function = "function";
pub const S_symbol = "symbol";
pub const S_instance = "instance";
pub const S_key = "key";
pub const S_any = "any";
pub const S_noval = "noval";
pub const S_nil = "nil";
pub const S_null = "null";
pub const S_number = "number";
pub const S_object = "object";
pub const S_string = "string";
pub const S_decimal = "decimal";
pub const S_integer = "integer";
pub const S_map = "map";
pub const S_scalar = "scalar";
pub const S_node = "node";
pub const S_parent = "parent";

// Character strings.
pub const S_BT = "`";
pub const S_CN = ":";
pub const S_CS = "]";
pub const S_DS = "$";
pub const S_DT = ".";
pub const S_FS = "/";
pub const S_KEY = "KEY";
pub const S_MT = "";
pub const S_OS = "[";
pub const S_SP = " ";
pub const S_CM = ",";
pub const S_VIZ = ": ";

// Type bits — using bit positions from 31 downward, matching the TS implementation.
pub const T_any: i32 = (1 << 31) - 1;
pub const T_noval: i32 = 1 << 30;
pub const T_boolean: i32 = 1 << 29;
pub const T_decimal: i32 = 1 << 28;
pub const T_integer: i32 = 1 << 27;
pub const T_number: i32 = 1 << 26;
pub const T_string: i32 = 1 << 25;
pub const T_function: i32 = 1 << 24;
pub const T_symbol: i32 = 1 << 23;
pub const T_null: i32 = 1 << 22;
// 7 bits reserved
pub const T_list: i32 = 1 << 14;
pub const T_map: i32 = 1 << 13;
pub const T_instance: i32 = 1 << 12;
// 4 bits reserved
pub const T_scalar: i32 = 1 << 7;
pub const T_node: i32 = 1 << 6;

// TYPENAME maps bit position (via leading zeros count) to type name string.
pub const TYPENAME = [_][]const u8{
    S_any,
    S_noval,
    S_boolean,
    S_decimal,
    S_integer,
    S_number,
    S_string,
    S_function,
    S_symbol,
    S_null,
    "", "", "",
    "", "", "", "",
    S_list,
    S_map,
    S_instance,
    "", "", "", "",
    S_scalar,
    S_node,
};

// Default max depth (for walk etc).
pub const MAXDEPTH: i32 = 32;

pub const MODENAME = std.StaticStringMap([]const u8).initComptime(.{
    .{ "4", "val" },
    .{ "1", "key:pre" },
    .{ "2", "key:post" },
});

// Value is a node — defined, and a map (object) or list (array).
pub fn isnode(val: JsonValue) bool {
    return switch (val) {
        .object, .array => true,
        else => false,
    };
}

// Value is a defined map (object) with string keys.
pub fn ismap(val: JsonValue) bool {
    return val == .object;
}

// Value is a defined list (array) with integer keys (indexes).
pub fn islist(val: JsonValue) bool {
    return val == .array;
}

// Value is a defined string (non-empty) or integer key.
pub fn iskey(val: JsonValue) bool {
    return switch (val) {
        .string => |s| s.len > 0,
        .integer => true,
        .float => true,
        else => false,
    };
}

// Check for an "empty" value — null, empty string, empty array, empty object.
pub fn isempty(val: JsonValue) bool {
    return switch (val) {
        .null => true,
        .string => |s| s.len == 0,
        .array => |a| a.data.items.len == 0,
        .object => |o| o.count() == 0,
        else => false,
    };
}

// Value is a function. JSON values are never functions.
pub fn isfunc(val: JsonValue) bool {
    return val == .function;
}

// Return a defined value, or an alternative if the value is null.
pub fn getdef(val: JsonValue, alt: JsonValue) JsonValue {
    return switch (val) {
        .null => alt,
        else => val,
    };
}

// Get the type name string from type bits.
pub fn typename(t: i64) []const u8 {
    if (t <= 0 or t > std.math.maxInt(u32)) return S_any;
    const ut: u32 = @intCast(t);
    const idx = @clz(ut);
    if (idx < TYPENAME.len and TYPENAME[idx].len > 0) {
        return TYPENAME[idx];
    }
    return S_any;
}

// Determine the type of a value as a bit code.
pub fn typify(val: JsonValue) i64 {
    return switch (val) {
        .object => @as(i64, T_node | T_map),
        .array => @as(i64, T_node | T_list),
        .integer => @as(i64, T_scalar | T_number | T_integer),
        .float => |f| {
            if (std.math.isNan(f)) {
                return @as(i64, T_noval);
            }
            if (!std.math.isInf(f) and f == @trunc(f)) {
                return @as(i64, T_scalar | T_number | T_integer);
            }
            return @as(i64, T_scalar | T_number | T_decimal);
        },
        .string => @as(i64, T_scalar | T_string),
        .bool => @as(i64, T_scalar | T_boolean),
        .null => @as(i64, T_scalar | T_null),
        .number_string => @as(i64, T_scalar | T_number),
        .function => @as(i64, T_scalar | T_function),
    };
}

// Get the integer size of a value.
pub fn size(val: JsonValue) i64 {
    return switch (val) {
        .array => |a| @intCast(a.data.items.len),
        .object => |o| @intCast(o.count()),
        .string => |s| @intCast(s.len),
        .integer => |i| i,
        .float => |f| @intFromFloat(@floor(f)),
        .bool => |b| if (b) @as(i64, 1) else @as(i64, 0),
        .null => 0,
        .number_string => 0,
        .function => 0,
    };
}

// Convert a key to its string representation.
// Returns a slice into existing data or a static string, or
// an allocated string for integer/float keys.
pub fn strkey(allocator: Allocator, key: JsonValue) ![]const u8 {
    return switch (key) {
        .string => |s| s,
        .integer => |i| try std.fmt.allocPrint(allocator, "{d}", .{i}),
        .float => |f| try std.fmt.allocPrint(allocator, "{d}", .{@as(i64, @intFromFloat(f))}),
        else => S_MT,
    };
}

// Get a list element by integer index. Only works on lists.
pub fn getelem(allocator: Allocator, val: JsonValue, key: JsonValue, alt: JsonValue) !JsonValue {
    if (val == .null or key == .null) return resolveAlt(allocator, alt);

    if (val != .array) return resolveAlt(allocator, alt);

    const list = val.array.data.items;

    // Get the key as string first
    const ks = try strkey(allocator, key);

    // Parse as integer
    const nkey_raw = std.fmt.parseInt(i64, ks, 10) catch return resolveAlt(allocator, alt);
    var nkey = nkey_raw;

    if (nkey < 0) {
        nkey = @as(i64, @intCast(list.len)) + nkey;
    }

    if (nkey >= 0 and nkey < @as(i64, @intCast(list.len))) {
        return list[@intCast(nkey)];
    }

    return resolveAlt(allocator, alt);
}

// If alt is a function, call it to get the default value.
fn resolveAlt(allocator: Allocator, alt: JsonValue) !JsonValue {
    if (alt == .function) return try alt.function(allocator);
    return alt;
}

// Safely get a property from a node (map or list).
pub fn getprop(allocator: Allocator, val: JsonValue, key: JsonValue, alt: JsonValue) !JsonValue {
    if (val == .null or key == .null) return alt;

    if (val == .object) {
        const ks = try strkey(allocator, key);
        if (val.object.get(ks)) |v| {
            return v;
        }
        return alt;
    }

    if (val == .array) {
        var ki: ?i64 = null;
        switch (key) {
            .integer => |i| ki = i,
            .float => |f| ki = @intFromFloat(f),
            .string => |s| {
                ki = std.fmt.parseInt(i64, s, 10) catch null;
            },
            else => {},
        }
        if (ki) |idx| {
            if (idx >= 0 and idx < @as(i64, @intCast(val.array.data.items.len))) {
                return val.array.data.items[@intCast(idx)];
            }
        }
        return alt;
    }

    return alt;
}

// Get sorted keys of a map, or indices (as strings) of a list.
// Returns a JsonValue array.
pub fn keysof(allocator: Allocator, val: JsonValue) !JsonValue {
    if (val == .object) {
        const obj = val.object;
        var key_strs = try std.ArrayList([]const u8).initCapacity(allocator, obj.count());
        defer key_strs.deinit();
        var it = obj.iterator();
        while (it.next()) |kv| {
            try key_strs.append(kv.key_ptr.*);
        }
        std.mem.sort([]const u8, key_strs.items, {}, stringLessThan);

        const arr_lr2 = try allocator.create(ListRef); arr_lr2.* = .{ .data = try ListData.initCapacity(allocator, obj.count()) }; const arr = arr_lr2;
        for (key_strs.items) |k| {
            try arr.append(JsonValue{ .string = k });
        }
        return JsonValue{ .array = arr };
    }

    if (val == .array) {
        const list = val.array.data.items;
        const arr_lr = try allocator.create(ListRef);
        arr_lr.* = .{ .data = try ListData.initCapacity(allocator, list.len) };
        const arr = arr_lr;
        for (0..list.len) |i| {
            const s = try std.fmt.allocPrint(allocator, "{d}", .{i});
            try arr.append(JsonValue{ .string = s });
        }
        return JsonValue{ .array = arr };
    }

    return try JsonValue.makeList(allocator);
}

fn stringLessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

// Check if a property with name key exists in node val.
pub fn haskey(allocator: Allocator, val: JsonValue, key: JsonValue) !bool {
    const result = try getprop(allocator, val, key, .null);
    return result != .null;
}

// List entries of a map or list as [key, value] pairs.
pub fn items(allocator: Allocator, val: JsonValue) !JsonValue {
    if (val == .object) {
        const obj = val.object;
        // Get sorted keys
        var key_strs = try std.ArrayList([]const u8).initCapacity(allocator, obj.count());
        defer key_strs.deinit();
        var it = obj.iterator();
        while (it.next()) |kv| {
            try key_strs.append(kv.key_ptr.*);
        }
        std.mem.sort([]const u8, key_strs.items, {}, stringLessThan);

        const arr_lr2 = try allocator.create(ListRef); arr_lr2.* = .{ .data = try ListData.initCapacity(allocator, obj.count()) }; const arr = arr_lr2;
        for (key_strs.items) |k| {
            const pair_lr = try allocator.create(ListRef);
        pair_lr.* = .{ .data = try ListData.initCapacity(allocator, 2) };
        const pair = pair_lr;
            try pair.append(JsonValue{ .string = k });
            try pair.append(obj.get(k).?);
            try arr.append(JsonValue{ .array = pair });
        }
        return JsonValue{ .array = arr };
    }

    if (val == .array) {
        const list = val.array.data.items;
        const arr_lr = try allocator.create(ListRef);
        arr_lr.* = .{ .data = try ListData.initCapacity(allocator, list.len) };
        const arr = arr_lr;
        for (list, 0..) |v, i| {
            const pair_lr = try allocator.create(ListRef);
        pair_lr.* = .{ .data = try ListData.initCapacity(allocator, 2) };
        const pair = pair_lr;
            const idx_str = try std.fmt.allocPrint(allocator, "{d}", .{i});
            try pair.append(JsonValue{ .string = idx_str });
            try pair.append(v);
            try arr.append(JsonValue{ .array = pair });
        }
        return JsonValue{ .array = arr };
    }

    return try JsonValue.makeList(allocator);
}

// Flatten nested arrays up to a specified depth.
pub fn flatten(allocator: Allocator, val: JsonValue, depth: i64) !JsonValue {
    if (val != .array) return val;
    const result = try flattenDepth(allocator, val.array.data.items, depth);
    return JsonValue{ .array = result };
}

fn flattenDepth(allocator: Allocator, arr: []const JsonValue, depth: i64) !*ListRef {
    const result_lr = try allocator.create(ListRef);
        result_lr.* = .{ .data = ListData.init(allocator) };
        const result = result_lr;
    for (arr) |item| {
        if (depth > 0 and item == .array) {
            const sub = try flattenDepth(allocator, item.array.data.items, depth - 1);
            for (sub.data.items) |subitem| {
                try result.append(subitem);
            }
        } else {
            try result.append(item);
        }
    }
    return result;
}

// Deep clone a JSON value.
pub fn clone(allocator: Allocator, val: JsonValue) !JsonValue {
    return switch (val) {
        .object => |obj| {
            const new_obj = try allocator.create(MapRef);
        new_obj.* = .{ .data = MapData.init(allocator) };
            try new_obj.data.ensureTotalCapacity(@intCast(obj.count()));
            var it = obj.iterator();
            while (it.next()) |kv| {
                const cloned_val = try clone(allocator, kv.value_ptr.*);
                try new_obj.put(kv.key_ptr.*, cloned_val);
            }
            return JsonValue{ .object = new_obj };
        },
        .array => |arr| {
            const new_arr_lr = try allocator.create(ListRef);
        new_arr_lr.* = .{ .data = try ListData.initCapacity(allocator, arr.data.items.len) };
        const new_arr = new_arr_lr;
            for (arr.data.items) |item| {
                const cloned_item = try clone(allocator, item);
                try new_arr.append(cloned_item);
            }
            return JsonValue{ .array = new_arr };
        },
        else => val,
    };
}

// Delete a property from a map or remove an element from a list.
pub fn delprop(allocator: Allocator, parent: JsonValue, key: JsonValue) !JsonValue {
    _ = allocator;
    if (!iskey(key)) return parent;

    if (parent == .object) {
        var obj = parent.object;
        var buf: [20]u8 = undefined;
        const ks = keyStr(&buf, key);
        _ = obj.fetchOrderedRemove(ks);
        return JsonValue{ .object = obj };
    }

    if (parent == .array) {
        var ki: ?i64 = null;
        switch (key) {
            .integer => |i| ki = i,
            .float => |f| ki = @intFromFloat(@trunc(f)),
            .string => |s| {
                ki = std.fmt.parseInt(i64, s, 10) catch null;
            },
            else => {},
        }
        if (ki) |idx| {
            const plen: i64 = @intCast(parent.array.data.items.len);
            // No negative index support for delprop
            if (idx >= 0 and idx < plen) {
                var arr = parent.array;
                _ = arr.orderedRemove(@intCast(idx));
                return JsonValue{ .array = arr };
            }
        }
        return parent;
    }

    return parent;
}

// Set a property value by key.
pub fn setprop(allocator: Allocator, parent: JsonValue, key: JsonValue, newval: JsonValue) !JsonValue {
    if (!iskey(key)) return parent;

    if (parent == .object) {
        var obj = parent.object;
        var buf: [20]u8 = undefined;
        const ks = keyStr(&buf, key);
        // Dupe the key if it was generated from the stack buffer (integer/float keys)
        const owned_key = if (key != .string)
            try allocator.dupe(u8, ks)
        else
            ks;
        try obj.put(owned_key, newval);
        return JsonValue{ .object = obj };
    }

    if (parent == .array) {
        var ki: ?i64 = null;
        switch (key) {
            .integer => |i| ki = i,
            .float => |f| ki = @intFromFloat(f),
            .string => |s| {
                ki = std.fmt.parseInt(i64, s, 10) catch null;
            },
            else => {},
        }
        if (ki) |idx| {
            var arr = parent.array;
            const plen: i64 = @intCast(arr.data.items.len);
            if (idx >= 0) {
                if (idx >= plen) {
                    // Append
                    try arr.append(newval);
                } else {
                    // Replace
                    arr.data.items[@intCast(idx)] = newval;
                }
            } else {
                // Prepend
                try arr.insert(0, newval);
            }
            return JsonValue{ .array = arr };
        }
        return parent;
    }

    return parent;
}

// Convert key to string without allocation, using a stack buffer.
fn keyStr(buf: *[20]u8, key: JsonValue) []const u8 {
    return switch (key) {
        .string => |s| s,
        .integer => |i| std.fmt.bufPrint(buf, "{d}", .{i}) catch S_MT,
        .float => |f| std.fmt.bufPrint(buf, "{d}", .{@as(i64, @intFromFloat(f))}) catch S_MT,
        else => S_MT,
    };
}

// Escape regex special characters.
pub fn escre(allocator: Allocator, s: []const u8) ![]const u8 {
    if (s.len == 0) return S_MT;
    var result = std.ArrayList(u8).init(allocator);
    for (s) |c| {
        if (isReSpecial(c)) {
            try result.append('\\');
        }
        try result.append(c);
    }
    return result.items;
}

fn isReSpecial(c: u8) bool {
    return switch (c) {
        '.', '*', '+', '?', '^', '$', '{', '}', '(', ')', '|', '[', ']', '\\' => true,
        else => false,
    };
}

// URL-encode a string.
pub fn escurl(allocator: Allocator, s: []const u8) ![]const u8 {
    if (s.len == 0) return S_MT;
    var result = std.ArrayList(u8).init(allocator);
    for (s) |c| {
        if (isUrlSafe(c)) {
            try result.append(c);
        } else {
            try result.appendSlice(try std.fmt.allocPrint(allocator, "%{X:0>2}", .{c}));
        }
    }
    return result.items;
}

fn isUrlSafe(c: u8) bool {
    // Match encodeURIComponent: unreserved chars per RFC 3986 plus !*'()
    return switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9', '-', '_', '.', '~', '!', '*', '\'', '(', ')' => true,
        else => false,
    };
}

// Join array elements into a string with separator handling.
pub fn join(allocator: Allocator, arr: JsonValue, sep: []const u8, urlMode: bool) ![]const u8 {
    if (arr != .array) return S_MT;

    const items_list = arr.array.data.items;
    const sarr: usize = items_list.len;

    // Filter to non-empty strings
    var filtered = std.ArrayList([]const u8).init(allocator);
    var indices = std.ArrayList(usize).init(allocator);
    for (items_list, 0..) |item, orig_idx| {
        if (item == .string and item.string.len > 0) {
            try filtered.append(item.string);
            try indices.append(orig_idx);
        }
    }

    if (filtered.items.len == 0) return S_MT;

    // Process separator handling
    var parts = std.ArrayList([]const u8).init(allocator);

    for (filtered.items, 0..) |s, fi| {
        var processed = s;
        const orig_idx = indices.items[fi];

        if (sep.len == 1) {
            const sep_c = sep[0];
            if (urlMode and orig_idx == 0) {
                // Remove trailing seps from first URL element
                processed = trimRight(processed, sep_c);
            } else {
                if (orig_idx > 0) {
                    // Remove leading seps
                    processed = trimLeft(processed, sep_c);
                }
                if (orig_idx < sarr - 1 or !urlMode) {
                    // Remove trailing seps
                    processed = trimRight(processed, sep_c);
                }
                // Collapse internal runs of sep
                processed = try collapseInternal(allocator, processed, sep_c);
            }
        }

        if (processed.len > 0) {
            try parts.append(processed);
        }
    }

    // Join with separator
    if (parts.items.len == 0) return S_MT;

    var total_len: usize = 0;
    for (parts.items) |p| total_len += p.len;
    total_len += sep.len * (parts.items.len - 1);

    var result = try std.ArrayList(u8).initCapacity(allocator, total_len);
    for (parts.items, 0..) |p, i| {
        try result.appendSlice(p);
        if (i < parts.items.len - 1) {
            try result.appendSlice(sep);
        }
    }
    return result.items;
}

fn trimLeft(s: []const u8, c: u8) []const u8 {
    var i: usize = 0;
    while (i < s.len and s[i] == c) : (i += 1) {}
    return s[i..];
}

fn trimRight(s: []const u8, c: u8) []const u8 {
    var end: usize = s.len;
    while (end > 0 and s[end - 1] == c) : (end -= 1) {}
    return s[0..end];
}

// Collapse internal runs of separator only when between non-separator chars.
// E.g. "c//d" → "c/d" but "//a" stays "//a".
fn collapseInternal(allocator: Allocator, s: []const u8, sep: u8) ![]const u8 {
    if (s.len < 3) return s;
    var result = std.ArrayList(u8).init(allocator);
    var i: usize = 0;
    while (i < s.len) {
        try result.append(s[i]);
        // If current char is not sep, look ahead for sep run followed by non-sep
        if (s[i] != sep) {
            if (i + 1 < s.len and s[i + 1] == sep) {
                var sep_end = i + 1;
                while (sep_end < s.len and s[sep_end] == sep) : (sep_end += 1) {}
                if (sep_end < s.len) {
                    // Sep run between two non-sep chars: collapse to single sep
                    try result.append(sep);
                    i = sep_end;
                    continue;
                }
                // Sep run at end: keep all
            }
        }
        i += 1;
    }
    return result.items;
}

// Output JSON with indentation.
pub fn jsonify(allocator: Allocator, val: JsonValue, indent_size: usize, offset: usize) ![]const u8 {
    if (val == .null) return "null";

    // Use the standard JSON stringify
    var result = std.ArrayList(u8).init(allocator);
    try jsonifyWrite(val, result.writer(), indent_size, offset, 0);
    return result.items;
}

fn jsonifyWrite(val: JsonValue, writer: anytype, indent_size: usize, offset: usize, depth: usize) !void {
    switch (val) {
        .null => try writer.writeAll("null"),
        .bool => |b| try writer.writeAll(if (b) "true" else "false"),
        .integer => |i| try writer.print("{d}", .{i}),
        .float => |f| {
            if (f == @trunc(f) and !std.math.isNan(f) and !std.math.isInf(f)) {
                try writer.print("{d}", .{@as(i64, @intFromFloat(f))});
            } else {
                try writer.print("{d}", .{f});
            }
        },
        .string => |s| {
            try writer.writeByte('"');
            for (s) |c| {
                switch (c) {
                    '"' => try writer.writeAll("\\\""),
                    '\\' => try writer.writeAll("\\\\"),
                    '\n' => try writer.writeAll("\\n"),
                    '\r' => try writer.writeAll("\\r"),
                    '\t' => try writer.writeAll("\\t"),
                    else => try writer.writeByte(c),
                }
            }
            try writer.writeByte('"');
        },
        .array => |arr| {
            if (arr.data.items.len == 0) {
                try writer.writeAll("[]");
                return;
            }
            try writer.writeAll("[\n");
            for (arr.data.items, 0..) |item, i| {
                try writeIndent(writer, offset + indent_size * (depth + 1));
                try jsonifyWrite(item, writer, indent_size, offset, depth + 1);
                if (i < arr.data.items.len - 1) {
                    try writer.writeByte(',');
                }
                try writer.writeByte('\n');
            }
            try writeIndent(writer, offset + indent_size * depth);
            try writer.writeByte(']');
        },
        .object => |obj| {
            if (obj.count() == 0) {
                try writer.writeAll("{}");
                return;
            }
            // Sort keys
            const allocator = std.heap.page_allocator;
            var key_list = std.ArrayList([]const u8).init(allocator);
            defer key_list.deinit();
            var it = obj.iterator();
            while (it.next()) |kv| {
                key_list.append(kv.key_ptr.*) catch return;
            }
            std.mem.sort([]const u8, key_list.items, {}, stringLessThan);

            try writer.writeAll("{\n");
            for (key_list.items, 0..) |k, i| {
                const v = obj.get(k).?;
                try writeIndent(writer, offset + indent_size * (depth + 1));
                try writer.writeByte('"');
                try writer.writeAll(k);
                try writer.writeAll("\": ");
                try jsonifyWrite(v, writer, indent_size, offset, depth + 1);
                if (i < key_list.items.len - 1) {
                    try writer.writeByte(',');
                }
                try writer.writeByte('\n');
            }
            try writeIndent(writer, offset + indent_size * depth);
            try writer.writeByte('}');
        },
        .number_string => |s| try writer.writeAll(s),
        .function => try writer.writeAll("null"),
    }
}

fn writeIndent(writer: anytype, count: usize) !void {
    for (0..count) |_| {
        try writer.writeByte(' ');
    }
}

// Compact JSON serialization (no whitespace) for partial injection stringification.
pub fn jsonifyCompact(allocator: Allocator, val: JsonValue) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    try jsonifyCompactWrite(val, result.writer());
    return result.items;
}

fn jsonifyCompactWrite(val: JsonValue, writer: anytype) !void {
    switch (val) {
        .null => try writer.writeAll("null"),
        .bool => |b| try writer.writeAll(if (b) "true" else "false"),
        .integer => |i| try writer.print("{d}", .{i}),
        .float => |f| try writer.print("{d}", .{f}),
        .string => |s| {
            try writer.writeByte('"');
            for (s) |c| {
                switch (c) {
                    '"' => try writer.writeAll("\\\""),
                    '\\' => try writer.writeAll("\\\\"),
                    '\n' => try writer.writeAll("\\n"),
                    '\r' => try writer.writeAll("\\r"),
                    '\t' => try writer.writeAll("\\t"),
                    else => try writer.writeByte(c),
                }
            }
            try writer.writeByte('"');
        },
        .array => |arr| {
            try writer.writeByte('[');
            for (arr.data.items, 0..) |item, i| {
                if (i > 0) try writer.writeByte(',');
                try jsonifyCompactWrite(item, writer);
            }
            try writer.writeByte(']');
        },
        .object => |obj| {
            try writer.writeByte('{');
            var first = true;
            var it = obj.iterator();
            while (it.next()) |kv| {
                if (!first) try writer.writeByte(',');
                first = false;
                try writer.writeByte('"');
                try writer.writeAll(kv.key_ptr.*);
                try writer.writeAll("\":");
                try jsonifyCompactWrite(kv.value_ptr.*, writer);
            }
            try writer.writeByte('}');
        },
        .number_string => |s| try writer.writeAll(s),
        .function => try writer.writeAll("null"),
    }
}

// Human-friendly string representation.
pub fn stringify(allocator: Allocator, val: JsonValue, maxlen: ?usize) ![]const u8 {
    return stringifyPretty(allocator, val, maxlen, false);
}

// Human-friendly string with optional ANSI color-coded nesting.
pub fn stringifyPretty(allocator: Allocator, val: JsonValue, maxlen: ?usize, pretty: bool) ![]const u8 {
    var jsonStr: []const u8 = undefined;
    if (pretty) {
        jsonStr = try stringifyColorInner(allocator, val, 0);
    } else {
        jsonStr = try stringifyInner(allocator, val);
    }

    if (maxlen) |ml| {
        if (ml > 0 and jsonStr.len > ml) {
            if (ml >= 3) {
                var truncated = try allocator.alloc(u8, ml);
                @memcpy(truncated[0 .. ml - 3], jsonStr[0 .. ml - 3]);
                truncated[ml - 3] = '.';
                truncated[ml - 2] = '.';
                truncated[ml - 1] = '.';
                return truncated;
            }
            return jsonStr[0..ml];
        }
    }

    return jsonStr;
}

// ANSI 256-color codes cycled per nesting depth, matching TS.
const PRETTY_COLORS = [_]u8{ 81, 118, 213, 39, 166, 154, 141, 203, 43, 45, 215, 75, 171, 119, 208, 85 };

fn stringifyColorInner(allocator: Allocator, val: JsonValue, depth: usize) ![]const u8 {
    const color_idx = depth % PRETTY_COLORS.len;
    const cc = PRETTY_COLORS[color_idx];
    const open_color = try std.fmt.allocPrint(allocator, "\x1b[38;5;{d}m", .{cc});
    const reset = "\x1b[0m";

    return switch (val) {
        .null => "null",
        .bool => |b| if (b) "true" else "false",
        .string => |s| s,
        .integer => |i| try std.fmt.allocPrint(allocator, "{d}", .{i}),
        .float => |f| blk: {
            if (f == @trunc(f) and !std.math.isNan(f) and !std.math.isInf(f)) {
                break :blk try std.fmt.allocPrint(allocator, "{d}", .{@as(i64, @intFromFloat(f))});
            }
            break :blk try std.fmt.allocPrint(allocator, "{d}", .{f});
        },
        .array => |arr| blk: {
            var result = std.ArrayList(u8).init(allocator);
            try result.appendSlice(open_color);
            try result.append('[');
            try result.appendSlice(reset);
            for (arr.data.items, 0..) |item, i| {
                const s = try stringifyColorInner(allocator, item, depth + 1);
                try result.appendSlice(s);
                if (i < arr.data.items.len - 1) try result.append(',');
            }
            try result.appendSlice(open_color);
            try result.append(']');
            try result.appendSlice(reset);
            break :blk result.items;
        },
        .object => |obj| blk: {
            var key_list = std.ArrayList([]const u8).init(allocator);
            var it = obj.iterator();
            while (it.next()) |kv| try key_list.append(kv.key_ptr.*);
            std.mem.sort([]const u8, key_list.items, {}, stringLessThan);

            var result = std.ArrayList(u8).init(allocator);
            try result.appendSlice(open_color);
            try result.append('{');
            try result.appendSlice(reset);
            for (key_list.items, 0..) |k, i| {
                const v = obj.get(k).?;
                try result.appendSlice(k);
                try result.append(':');
                const s = try stringifyColorInner(allocator, v, depth + 1);
                try result.appendSlice(s);
                if (i < key_list.items.len - 1) try result.append(',');
            }
            try result.appendSlice(open_color);
            try result.append('}');
            try result.appendSlice(reset);
            break :blk result.items;
        },
        .number_string => |s| s,
        .function => "",
    };
}

fn stringifyInner(allocator: Allocator, val: JsonValue) ![]const u8 {
    return switch (val) {
        .null => "null",
        .bool => |b| if (b) "true" else "false",
        .string => |s| s,
        .integer => |i| try std.fmt.allocPrint(allocator, "{d}", .{i}),
        .float => |f| {
            if (f == @trunc(f) and !std.math.isNan(f) and !std.math.isInf(f)) {
                return try std.fmt.allocPrint(allocator, "{d}", .{@as(i64, @intFromFloat(f))});
            }
            return try std.fmt.allocPrint(allocator, "{d}", .{f});
        },
        .array => |arr| {
            var result = std.ArrayList(u8).init(allocator);
            try result.append('[');
            for (arr.data.items, 0..) |item, i| {
                const s = try stringifyInner(allocator, item);
                try result.appendSlice(s);
                if (i < arr.data.items.len - 1) {
                    try result.append(',');
                }
            }
            try result.append(']');
            return result.items;
        },
        .object => |obj| {
            // Sort keys
            var key_list = std.ArrayList([]const u8).init(allocator);
            defer key_list.deinit();
            var it = obj.iterator();
            while (it.next()) |kv| {
                try key_list.append(kv.key_ptr.*);
            }
            std.mem.sort([]const u8, key_list.items, {}, stringLessThan);

            var result = std.ArrayList(u8).init(allocator);
            try result.append('{');
            for (key_list.items, 0..) |k, i| {
                const v = obj.get(k).?;
                try result.appendSlice(k);
                try result.append(':');
                const s = try stringifyInner(allocator, v);
                try result.appendSlice(s);
                if (i < key_list.items.len - 1) {
                    try result.append(',');
                }
            }
            try result.append('}');
            return result.items;
        },
        .number_string => |s| s,
        .function => "",
    };
}

// Build a human-friendly path string.
pub fn pathify(allocator: Allocator, val: JsonValue, from: usize, end: usize) ![]const u8 {
    var path: ?std.ArrayList([]const u8) = null;

    if (val == .array) {
        path = std.ArrayList([]const u8).init(allocator);
        for (val.array.data.items) |item| {
            switch (item) {
                .string => |s| try path.?.append(s),
                .integer => |i| try path.?.append(try std.fmt.allocPrint(allocator, "{d}", .{i})),
                .float => |f| try path.?.append(try std.fmt.allocPrint(allocator, "{d}", .{@as(i64, @intFromFloat(f))})),
                else => {},
            }
        }
    } else if (val == .string) {
        path = std.ArrayList([]const u8).init(allocator);
        try path.?.append(val.string);
    } else if (val == .integer or val == .float) {
        path = std.ArrayList([]const u8).init(allocator);
        const num: i64 = if (val == .integer) val.integer else @intFromFloat(@floor(val.float));
        try path.?.append(try std.fmt.allocPrint(allocator, "{d}", .{num}));
    }

    if (path) |p| {
        const start = if (from > p.items.len) p.items.len else from;
        const end_idx = if (p.items.len < end) start else if (p.items.len - end < start) start else p.items.len - end;

        const sliced = p.items[start..end_idx];

        if (sliced.len == 0) {
            return "<root>";
        }

        // Map: replace dots in string parts
        var mapped = std.ArrayList([]const u8).init(allocator);
        for (sliced) |part| {
            var replaced = std.ArrayList(u8).init(allocator);
            for (part) |c| {
                if (c != '.') try replaced.append(c);
            }
            try mapped.append(replaced.items);
        }

        // Join with dots
        var result = std.ArrayList(u8).init(allocator);
        for (mapped.items, 0..) |part, i| {
            try result.appendSlice(part);
            if (i < mapped.items.len - 1) {
                try result.append('.');
            }
        }
        return result.items;
    }

    // Unknown path — always include colon and stringified value
    var result = std.ArrayList(u8).init(allocator);
    try result.appendSlice("<unknown-path:");
    const s = try stringify(allocator, val, 47);
    try result.appendSlice(s);
    try result.append('>');
    return result.items;
}

// Slice: extract part of an array, string, or clamp a number.
pub fn slice(allocator: Allocator, val: JsonValue, start_in: ?i64, end_in: ?i64) !JsonValue {
    return sliceMut(allocator, val, start_in, end_in, false);
}

// Slice with optional in-place mutation for arrays (matches TS mutate param).
pub fn sliceMut(allocator: Allocator, val: JsonValue, start_in: ?i64, end_in: ?i64, mutate: bool) !JsonValue {
    _ = mutate;
    // Number case: clamp
    if (val != .string and val != .array and val != .object) {
        if (val == .integer or val == .float) {
            const f: f64 = if (val == .integer) @floatFromInt(val.integer) else val.float;
            var lo: f64 = -std.math.floatMax(f64);
            var hi: f64 = std.math.floatMax(f64);
            if (start_in) |s| {
                lo = @floatFromInt(s);
            }
            if (end_in) |e| {
                hi = @floatFromInt(e - 1);
            }
            const clamped = @min(@max(f, lo), hi);
            // Return as integer if the original was integer
            if (clamped == @trunc(clamped)) {
                return JsonValue{ .integer = @intFromFloat(clamped) };
            }
            return JsonValue{ .float = clamped };
        }
        // bool, null, object: return as-is
        return val;
    }

    const vlen: i64 = size(val);

    // If end is specified but start is not, default start to 0
    var eff_start = start_in;
    if (end_in != null and eff_start == null) {
        eff_start = 0;
    }

    if (eff_start == null) return val;

    var start = eff_start.?;
    var end_val = vlen;

    if (start < 0) {
        end_val = vlen + start;
        if (end_val < 0) end_val = 0;
        start = 0;
    } else if (end_in) |e| {
        end_val = e;
        if (end_val < 0) {
            end_val = vlen + end_val;
            if (end_val < 0) end_val = 0;
        } else if (vlen < end_val) {
            end_val = vlen;
        }
    }

    if (vlen < start) start = vlen;

    if (start >= 0 and start <= end_val and end_val <= vlen) {
        if (val == .array) {
            const s_usize: usize = @intCast(start);
            const e_usize: usize = @intCast(end_val);
            const src = val.array.data.items[s_usize..e_usize];
            const new_arr_lr = try allocator.create(ListRef);
        new_arr_lr.* = .{ .data = try ListData.initCapacity(allocator, src.len) };
        const new_arr = new_arr_lr;
            for (src) |item| {
                try new_arr.append(item);
            }
            return JsonValue{ .array = new_arr };
        }
        if (val == .string) {
            const s_usize: usize = @intCast(start);
            const e_usize: usize = @intCast(end_val);
            return JsonValue{ .string = val.string[s_usize..e_usize] };
        }
    } else {
        if (val == .array) {
            const empty_arr_lr = try allocator.create(ListRef);
        empty_arr_lr.* = .{ .data = ListData.init(allocator) };
        const empty_arr = empty_arr_lr;
            _ = &empty_arr;
            return JsonValue{ .array = empty_arr };
        }
        if (val == .string) {
            return JsonValue{ .string = S_MT };
        }
    }

    return val;
}

// Pad a string to a target length.
pub fn pad(allocator: Allocator, s: []const u8, padding: i64, padchar: u8) ![]const u8 {
    if (padding >= 0) {
        const target: usize = @intCast(padding);
        if (s.len >= target) return s;
        var result = try allocator.alloc(u8, target);
        @memcpy(result[0..s.len], s);
        @memset(result[s.len..], padchar);
        return result;
    } else {
        const target: usize = @intCast(-padding);
        if (s.len >= target) return s;
        const pad_len = target - s.len;
        var result = try allocator.alloc(u8, target);
        @memset(result[0..pad_len], padchar);
        @memcpy(result[pad_len..], s);
        return result;
    }
}

// ============================================================================
// Walk — depth-first tree traversal with before/after callbacks.
// ============================================================================

// Pool of path buffers — one std.ArrayList([]const u8) per depth. Allocated
// once per top-level walk() call, grown on demand, and mutated in place as
// siblings are visited. Avoids allocating a fresh path slice per recursive
// call. Buffers are heap-allocated so that growing the outer list (on
// deeper recursion) does not invalidate pointers held by shallower frames.
const WalkPool = struct {
    allocator: Allocator,
    buffers: std.ArrayList(*std.ArrayList([]const u8)),

    fn init(allocator: Allocator) WalkPool {
        return .{
            .allocator = allocator,
            .buffers = std.ArrayList(*std.ArrayList([]const u8)).init(allocator),
        };
    }

    fn deinit(self: *WalkPool) void {
        for (self.buffers.items) |buf| {
            buf.deinit();
            self.allocator.destroy(buf);
        }
        self.buffers.deinit();
    }

    // Return the path buffer for the given depth, growing the pool if needed.
    fn at(self: *WalkPool, depth: usize) !*std.ArrayList([]const u8) {
        while (self.buffers.items.len <= depth) {
            const buf = try self.allocator.create(std.ArrayList([]const u8));
            buf.* = std.ArrayList([]const u8).init(self.allocator);
            try self.buffers.append(buf);
        }
        return self.buffers.items[depth];
    }
};

// Depth-first walk callback. The `path` slice is a shared, mutable buffer
// reused across all callback invocations for the lifetime of this top-level
// walk() call. Callbacks that need to retain the path MUST copy it
// (e.g. `allocator.dupe([]const u8, path)`); otherwise its contents will be
// overwritten by subsequent visits.
pub const WalkApply = *const fn (
    allocator: Allocator,
    key: ?[]const u8,
    val: JsonValue,
    parent: JsonValue,
    path: []const []const u8,
) anyerror!JsonValue;

pub fn walk(
    allocator: Allocator,
    val: JsonValue,
    before: ?WalkApply,
    after: ?WalkApply,
    maxdepth: i32,
) !JsonValue {
    var pool = WalkPool.init(allocator);
    defer pool.deinit();

    // Depth 0 path buffer (empty) — the root has no path entries.
    const root_buf = try pool.at(0);
    root_buf.clearRetainingCapacity();

    return walkDescend(allocator, &pool, val, before, after, maxdepth, null, .null, root_buf.items);
}

fn walkDescend(
    allocator: Allocator,
    pool: *WalkPool,
    val_in: JsonValue,
    before: ?WalkApply,
    after: ?WalkApply,
    maxdepth: i32,
    key: ?[]const u8,
    parent: JsonValue,
    path: []const []const u8,
) !JsonValue {
    var out = val_in;

    // Apply before callback.
    if (before) |apply| {
        out = try apply(allocator, key, out, parent, path);
    }

    // Check depth limit.
    if (maxdepth == 0 or (path.len > 0 and maxdepth > 0 and maxdepth <= @as(i32, @intCast(path.len)))) {
        return out;
    }

    if (isnode(out)) {
        // Get items (sorted key-value pairs).
        const kv_pairs = try items(allocator, out);
        if (kv_pairs == .array) {
            const depth = path.len;
            const child_depth = depth + 1;

            // Get (or create) the shared path buffer for this child depth,
            // and sync the prefix [0..depth] from the current path. Only
            // needed once per parent: siblings share the same prefix and
            // each overwrites slot [depth] below.
            const child_buf = try pool.at(child_depth);
            try child_buf.resize(child_depth);
            var i: usize = 0;
            while (i < depth) : (i += 1) {
                child_buf.items[i] = path[i];
            }

            for (kv_pairs.array.data.items) |pair| {
                if (pair != .array or pair.array.data.items.len < 2) continue;
                const ckey_val = pair.array.data.items[0];
                const child = pair.array.data.items[1];
                const ckey = if (ckey_val == .string) ckey_val.string else "";

                // Overwrite the last path slot for this sibling. The buffer
                // is shared across siblings — callbacks must copy the path
                // if they want to retain it.
                child_buf.items[depth] = ckey;

                const new_child = try walkDescend(
                    allocator,
                    pool,
                    child,
                    before,
                    after,
                    maxdepth,
                    ckey,
                    out,
                    child_buf.items,
                );

                // Update the output with the new child value.
                out = try setprop(allocator, out, ckey_val, new_child);
            }
        }
    }

    // Apply after callback.
    if (after) |apply| {
        out = try apply(allocator, key, out, parent, path);
    }

    return out;
}

// ============================================================================
// Merge — deep-merge a list of values. Later values override.
// ============================================================================

pub fn merge(allocator: Allocator, val: JsonValue, maxdepth: i32) !JsonValue {
    if (val != .array) return val;

    const list = val.array.data.items;
    if (list.len == 0) return .null;
    if (list.len == 1) return list[0];

    const md: i32 = if (maxdepth < 0) 0 else maxdepth;

    // Special case: depth 0 returns empty container of last element's type.
    if (md == 0) {
        const last = list[list.len - 1];
        if (islist(last)) return try JsonValue.makeList(allocator);
        if (ismap(last)) {
            const obj = try allocator.create(MapRef);
        obj.* = .{ .data = MapData.init(allocator) };
            _ = &obj;
            return JsonValue{ .object = obj };
        }
        return last;
    }

    // Use first element directly (not cloned) — matches TS/Go in-place
    // mutation semantics. With *MapRef/*ListRef, callers holding list[0]
    // see the merged result.
    var out = list[0];

    for (list[1..]) |obj| {
        if (!isnode(obj)) {
            out = obj;
        } else {
            out = try mergeNodes(allocator, out, obj, md, 0);
        }
    }

    return out;
}

fn mergeNodes(
    allocator: Allocator,
    dst: JsonValue,
    src: JsonValue,
    maxdepth: i32,
    depth: i32,
) !JsonValue {
    // At depth limit: just replace.
    if (maxdepth > 0 and depth >= maxdepth) {
        return src;
    }

    if (!isnode(src)) return src;
    if (!isnode(dst)) return try clone(allocator, src);

    // Types differ: src wins.
    if ((ismap(src) and !ismap(dst)) or (islist(src) and !islist(dst))) {
        return try clone(allocator, src);
    }

    // Both maps: deep merge.
    if (ismap(src) and ismap(dst)) {
        var result = try clone(allocator, dst);
        var it = src.object.iterator();
        while (it.next()) |kv| {
            const key_str = kv.key_ptr.*;
            const src_val = kv.value_ptr.*;
            const key_json = JsonValue{ .string = key_str };

            if (result.object.get(key_str)) |dst_val| {
                if (isnode(src_val) and isnode(dst_val)) {
                    const merged = try mergeNodes(allocator, dst_val, src_val, maxdepth, depth + 1);
                    result = try setprop(allocator, result, key_json, merged);
                } else {
                    result = try setprop(allocator, result, key_json, src_val);
                }
            } else {
                result = try setprop(allocator, result, key_json, src_val);
            }
        }
        return result;
    }

    // Both lists: element-by-element overlay.
    if (islist(src) and islist(dst)) {
        var result = try clone(allocator, dst);
        for (src.array.data.items, 0..) |item, i| {
            const idx_json = JsonValue{ .integer = @intCast(i) };
            if (i < dst.array.data.items.len) {
                const dst_item = dst.array.data.items[i];
                if (isnode(item) and isnode(dst_item)) {
                    const merged = try mergeNodes(allocator, dst_item, item, maxdepth, depth + 1);
                    result = try setprop(allocator, result, idx_json, merged);
                } else {
                    result = try setprop(allocator, result, idx_json, item);
                }
            } else {
                result = try setprop(allocator, result, idx_json, item);
            }
        }
        return result;
    }

    return src;
}

// ============================================================================
// GetPath — resolve a dotted path string against a store.
// ============================================================================

pub fn getpath(allocator: Allocator, path_val: JsonValue, store: JsonValue) anyerror!JsonValue {
    return getpathInj(allocator, path_val, store, null);
}

pub fn getpathInj(allocator: Allocator, path_val: JsonValue, store: JsonValue, inj: ?*Injection) anyerror!JsonValue {
    var parts_buf: [64][]const u8 = undefined;
    var numparts: usize = 0;

    // Parse path into parts.
    switch (path_val) {
        .string => |s| {
            if (s.len == 0) {
                parts_buf[0] = S_MT;
                numparts = 1;
            } else {
                var it = std.mem.splitScalar(u8, s, '.');
                while (it.next()) |part| {
                    if (numparts < parts_buf.len) {
                        parts_buf[numparts] = part;
                        numparts += 1;
                    }
                }
            }
        },
        .array => |arr| {
            for (arr.data.items) |item| {
                if (numparts < parts_buf.len) {
                    parts_buf[numparts] = if (item == .string) item.string else "";
                    numparts += 1;
                }
            }
        },
        .null => {
            // Null path without injection → return null.
            // With injection, null path returns the source.
            if (inj == null) return .null;
            return getpropFromStore(store);
        },
        else => return .null,
    }

    const parts = parts_buf[0..numparts];

    // Single empty part (empty string path) → return source/dparent.
    // But NOT for multiple empty parts (.. ancestor paths).
    if (numparts == 1 and parts[0].len == 0) {
        if (inj) |ij| return ij.dparent;
        return getpropFromStore(store);
    }
    // Single "." (splits to ["",""]) → return dparent.
    if (numparts == 2 and parts[0].len == 0 and parts[1].len == 0) {
        if (inj) |ij| return ij.dparent;
        return getpropFromStore(store);
    }

    // Single part: check store directly first (for $ commands etc).
    if (numparts == 1) {
        if (store == .object) {
            if (store.object.get(parts[0])) |v| {
                // If the value is a function, call it.
                if (v == .function) return try v.function(allocator);
                return v;
            }
        }
    }

    // Resolve through $TOP (or dparent for relative paths).
    var val = getpropFromStore(store);

    // Meta-path syntax: "name$~rest" or "name$=rest" on the first part.
    if (numparts > 0 and inj != null and inj.?.meta != .null) {
        const first = parts[0];
        // Find "$~" or "$=" in first part.
        if (std.mem.indexOf(u8, first, "$~") orelse std.mem.indexOf(u8, first, "$=")) |dpos| {
            const meta_key = first[0..dpos];
            const rest = first[dpos + 2 ..];
            val = try getprop(allocator, inj.?.meta, JsonValue{ .string = meta_key }, .null);
            parts_buf[0] = rest;
        }
    }

    var pI: usize = 0;
    while (pI < numparts) : (pI += 1) {
        if (val == .null) break;
        const part = parts[pI];

        // Handle $REF:subpath$ — resolve subpath in $SPEC, use result as part.
        if (inj != null and part.len > 5 and std.mem.startsWith(u8, part, "$REF:") and part[part.len - 1] == '$') {
            const subpath = part[5 .. part.len - 1];
            const spec_val = if (store == .object) store.object.get(S_DSPEC) orelse .null else .null;
            if (spec_val != .null) {
                const result = try getpath(allocator, JsonValue{ .string = subpath }, spec_val);
                const effective = try stringify(allocator, result, null);
                val = try resolvePart(allocator, val, effective, inj);
            }
            continue;
        }

        // Handle $GET:subpath$ — resolve subpath in store data, use result as part.
        if (inj != null and part.len > 5 and std.mem.startsWith(u8, part, "$GET:") and part[part.len - 1] == '$') {
            const subpath = part[5 .. part.len - 1];
            const result = try getpath(allocator, JsonValue{ .string = subpath }, store);
            const effective = try stringify(allocator, result, null);
            val = try resolvePart(allocator, val, effective, inj);
            continue;
        }

        // Handle $META:subpath$ — resolve subpath in injection metadata.
        if (inj != null and part.len > 6 and std.mem.startsWith(u8, part, "$META:") and part[part.len - 1] == '$') {
            const subpath = part[6 .. part.len - 1];
            const ij = inj.?;
            if (ij.meta != .null) {
                const result = try getpathInj(allocator, JsonValue{ .string = subpath }, ij.meta, null);
                const effective = try stringify(allocator, result, null);
                val = try resolvePart(allocator, val, effective, inj);
            }
            continue;
        }

        // Handle empty parts (from consecutive dots): ancestor traversal.
        if (part.len == 0) {
            // Count consecutive empty parts as ascend levels.
            var ascends: usize = 0;
            while (pI + 1 < numparts and parts[pI + 1].len == 0) {
                ascends += 1;
                pI += 1;
            }

            if (inj != null and ascends > 0) {
                const ij = inj.?;
                // Last group of dots with no trailing part: adjust.
                if (pI == numparts - 1) {
                    if (ascends > 0) ascends -= 1;
                }

                if (ascends == 0) {
                    val = ij.dparent;
                } else {
                    // Build full path from dpath minus ascends, plus remaining parts.
                    const dpath = ij.dpath;
                    const cutLen = if (ascends > dpath.len) 0 else dpath.len - ascends;
                    var fullpath = std.ArrayList([]const u8).init(allocator);
                    for (dpath[0..cutLen]) |dp| try fullpath.append(dp);
                    if (pI + 1 < numparts) {
                        for (parts[pI + 1 .. numparts]) |rp| try fullpath.append(rp);
                    }
                    if (ascends <= dpath.len) {
                        // Walk the fullpath array against the store directly.
                        var resolved = store;
                        var prev_fp: []const u8 = "";
                        for (fullpath.items) |fp| {
                            if (resolved == .null) break;
                            // Skip synthetic $: markers.
                            if (fp.len > 2 and std.mem.startsWith(u8, fp, "$:")) continue;
                            // Skip duplicate consecutive $TOP entries.
                            if (std.mem.eql(u8, fp, S_DTOP) and std.mem.eql(u8, prev_fp, S_DTOP)) continue;
                            prev_fp = fp;
                            if (resolved == .object) {
                                if (resolved.object.get(fp)) |v| {
                                    resolved = v;
                                } else {
                                    resolved = .null;
                                }
                            } else if (resolved == .array) {
                                const idx = std.fmt.parseInt(i64, fp, 10) catch {
                                    resolved = .null;
                                    break;
                                };
                                if (idx >= 0 and idx < @as(i64, @intCast(resolved.array.data.items.len))) {
                                    resolved = resolved.array.data.items[@intCast(idx)];
                                } else {
                                    resolved = .null;
                                }
                            } else {
                                resolved = .null;
                            }
                        }
                        val = resolved;
                    } else {
                        val = .null;
                    }
                    return val;
                }
            } else {
                val = if (inj) |ij| ij.dparent else val;
            }
            continue;
        }

        val = try resolvePart(allocator, val, part, inj);
    }

    return val;
}

fn resolvePart(allocator: Allocator, val: JsonValue, part_in: []const u8, inj: ?*const Injection) !JsonValue {
    // Handle $$ escape → $.
    var part = part_in;
    if (std.mem.indexOf(u8, part, "$$")) |_| {
        var buf = std.ArrayList(u8).init(allocator);
        var i: usize = 0;
        while (i < part.len) {
            if (i + 1 < part.len and part[i] == '$' and part[i + 1] == '$') {
                buf.append('$') catch {};
                i += 2;
            } else {
                buf.append(part[i]) catch {};
                i += 1;
            }
        }
        part = buf.items;
    }

    // Handle $KEY → replace with injection key.
    if (std.mem.eql(u8, part, "$KEY")) {
        if (inj) |ij| {
            part = ij.key;
        }
    }

    if (val == .object) {
        return val.object.get(part) orelse .null;
    } else if (val == .array) {
        const idx = std.fmt.parseInt(i64, part, 10) catch return .null;
        if (idx >= 0 and idx < @as(i64, @intCast(val.array.data.items.len))) {
            return val.array.data.items[@intCast(idx)];
        }
        return .null;
    }
    return .null;
}

fn getpropFromStore(store: JsonValue) JsonValue {
    if (store == .object) {
        return store.object.get(S_DTOP) orelse store;
    }
    return store;
}

// ============================================================================
// SetPath — set a value at a dotted path in a store.
// ============================================================================

pub fn setpath(allocator: Allocator, store: JsonValue, path_val: JsonValue, val: JsonValue) !JsonValue {
    var parts_buf: [64][]const u8 = undefined;
    var is_numeric: [64]bool = undefined;
    var numparts: usize = 0;

    switch (path_val) {
        .string => |s| {
            var it = std.mem.splitScalar(u8, s, '.');
            while (it.next()) |part| {
                if (numparts < parts_buf.len) {
                    parts_buf[numparts] = part;
                    is_numeric[numparts] = false;
                    numparts += 1;
                }
            }
        },
        .array => |arr| {
            for (arr.data.items) |item| {
                if (numparts < parts_buf.len) {
                    switch (item) {
                        .string => |s| {
                            parts_buf[numparts] = s;
                            is_numeric[numparts] = false;
                        },
                        .integer => |i| {
                            parts_buf[numparts] = std.fmt.allocPrint(allocator, "{d}", .{i}) catch "";
                            is_numeric[numparts] = true;
                        },
                        else => {
                            parts_buf[numparts] = "";
                            is_numeric[numparts] = false;
                        },
                    }
                    numparts += 1;
                }
            }
        },
        else => return store,
    }

    if (numparts == 0) return store;

    const parts = parts_buf[0..numparts];
    var parent = getpropFromStore(store);

    // Navigate to the parent of the final key, creating nodes as needed.
    var i: usize = 0;
    while (i < numparts - 1) : (i += 1) {
        const part = parts[i];
        const key_json = JsonValue{ .string = part };
        var next = try getprop(allocator, parent, key_json, .null);
        if (!isnode(next)) {
            // Create array if the next part is a numeric from an array path, else object.
            if (i + 1 < numparts and is_numeric[i + 1]) {
                next = try JsonValue.makeList(allocator);
            } else {
                next = try JsonValue.makeMap(allocator);
            }
            parent = try setprop(allocator, parent, key_json, next);
        }
        parent = next;
    }

    // Set the final value. Return the modified parent node.
    const last_key = JsonValue{ .string = parts[numparts - 1] };
    return try setprop(allocator, parent, last_key, val);
}

// ============================================================================
// Injection — state carried through recursive spec injection.
// Mirrors the Go/TS Injection struct for three-phase key processing.
// ============================================================================

// Modify callback — called after each injection step to post-process values.
pub const ModifyFn = *const fn (
    allocator: Allocator,
    val: JsonValue,
    key: []const u8,
    parent: JsonValue,
    inj: *Injection,
    store: JsonValue,
) void;

pub const Injection = struct {
    allocator: Allocator,
    mode: i32 = M_VAL,
    full: bool = false,
    skip: bool = false, // Set by handlers to suppress setval.
    validate_mode: bool = false, // Enables $STRING/$NUMBER/etc validation commands.
    exact_mode: bool = false, // Exact matching mode for select.
    key_i: usize = 0,
    key: []const u8 = S_DTOP,
    val: JsonValue = .null,
    parent: JsonValue = .null,
    base: []const u8 = S_DTOP,
    prior: ?*Injection = null,
    dparent: JsonValue = .null,

    // Heap-allocated slices from the arena.
    keys: [][]const u8,
    path: [][]const u8,
    nodes: []JsonValue,
    dpath: [][]const u8,

    // Metadata for injection context.
    meta: JsonValue = .null,

    // Optional modify callback — called after each injection step.
    modify: ?ModifyFn = null,

    // Shared error collector (pointer so all children share it).
    errs: *std.ArrayList([]const u8),

    // Create a child injection for processing key at keys[key_i].
    pub fn child(self: *Injection, key_i: usize, keys: []const []const u8) !*Injection {
        const a = self.allocator;
        const k = if (key_i < keys.len) keys[key_i] else S_MT;

        // Extend path: parent path + new key.
        var new_path = try a.alloc([]const u8, self.path.len + 1);
        @memcpy(new_path[0..self.path.len], self.path);
        new_path[self.path.len] = k;

        // Extend nodes: parent nodes + current val.
        var new_nodes = try a.alloc(JsonValue, self.nodes.len + 1);
        @memcpy(new_nodes[0..self.nodes.len], self.nodes);
        new_nodes[self.nodes.len] = self.val;

        // Copy dpath.
        const new_dpath = try a.alloc([]const u8, self.dpath.len);
        @memcpy(new_dpath, self.dpath);

        // Copy keys.
        const new_keys = try a.alloc([]const u8, keys.len);
        @memcpy(new_keys, keys);

        const c = try a.create(Injection);
        c.* = Injection{
            .allocator = a,
            .mode = self.mode,
            .full = false,
            .key_i = key_i,
            .key = k,
            .val = getprop(a, self.val, JsonValue{ .string = k }, .null) catch .null,
            .parent = self.val,
            .base = self.base,
            .prior = self,
            .dparent = self.dparent,
            .keys = new_keys,
            .path = new_path,
            .nodes = new_nodes,
            .dpath = new_dpath,
            .meta = self.meta,
            .modify = self.modify,
            .validate_mode = self.validate_mode,
            .exact_mode = self.exact_mode,
            .errs = self.errs,
        };
        return c;
    }

    // Set a value in the parent node (or an ancestor).
    pub fn setval(self: *Injection, val: JsonValue, ancestor: usize) !JsonValue {
        const a = self.allocator;
        if (ancestor < 2) {
            if (val == .null) {
                self.parent = delprop(a, self.parent, JsonValue{ .string = self.key }) catch self.parent;
            } else {
                self.parent = setprop(a, self.parent, JsonValue{ .string = self.key }, val) catch self.parent;
            }
            return self.parent;
        } else {
            // Ancestor access via nodes/path.
            const nlen = self.nodes.len;
            const plen = self.path.len;
            if (ancestor > nlen or ancestor > plen) return self.parent;
            const aval = self.nodes[nlen - ancestor];
            const akey = self.path[plen - ancestor];
            if (val == .null) {
                _ = delprop(a, aval, JsonValue{ .string = akey }) catch {};
            } else {
                _ = setprop(a, aval, JsonValue{ .string = akey }, val) catch {};
            }
            return aval;
        }
    }

    // Advance dparent down the data tree based on the current path.
    pub fn descend(self: *Injection) void {
        const a = self.allocator;
        var parentkey: []const u8 = S_MT;
        if (self.path.len >= 2) {
            parentkey = self.path[self.path.len - 2];
        }

        if (self.dparent == .null) {
            if (self.dpath.len > 1) {
                self.dpath = appendSlice(a, []const u8, self.dpath, parentkey) catch self.dpath;
            }
        } else {
            if (parentkey.len > 0) {
                self.dparent = getprop(a, self.dparent, JsonValue{ .string = parentkey }, .null) catch .null;

                const lastpart: []const u8 = if (self.dpath.len > 0)
                    self.dpath[self.dpath.len - 1]
                else
                    S_MT;

                // Check for synthetic path marker "$:key".
                const marker = std.fmt.allocPrint(a, "$:{s}", .{parentkey}) catch S_MT;
                if (std.mem.eql(u8, lastpart, marker)) {
                    // Pop synthetic marker.
                    self.dpath = self.dpath[0 .. self.dpath.len - 1];
                } else {
                    self.dpath = appendSlice(a, []const u8, self.dpath, parentkey) catch self.dpath;
                }
            }
        }
    }
};

fn appendSlice(allocator: Allocator, comptime T: type, existing: []const T, item: T) ![]T {
    var new = try allocator.alloc(T, existing.len + 1);
    @memcpy(new[0..existing.len], existing);
    new[existing.len] = item;
    return new;
}

// ============================================================================
// Inject — core injection function with three-phase key processing.
// ============================================================================

pub fn injectVal(allocator: Allocator, val: JsonValue, store: JsonValue, inj_opt: ?*Injection) anyerror!JsonValue {
    var inj: *Injection = undefined;

    if (inj_opt == null or (inj_opt != null and inj_opt.?.mode == 0)) {
        // Root injection: wrap val in a virtual parent.
        const parent_obj = try allocator.create(MapRef);
        parent_obj.* = .{ .data = MapData.init(allocator) };
        try parent_obj.put(S_DTOP, val);
        const parent_val = JsonValue{ .object = parent_obj };

        var errs: *std.ArrayList([]const u8) = undefined;
        if (inj_opt) |existing| {
            errs = existing.errs;
        } else {
            errs = try allocator.create(std.ArrayList([]const u8));
            errs.* = std.ArrayList([]const u8).init(allocator);
        }

        var init_keys = try allocator.alloc([]const u8, 1);
        init_keys[0] = S_DTOP;
        var init_path = try allocator.alloc([]const u8, 1);
        init_path[0] = S_DTOP;
        var init_nodes = try allocator.alloc(JsonValue, 1);
        init_nodes[0] = parent_val;
        var init_dpath = try allocator.alloc([]const u8, 1);
        init_dpath[0] = S_DTOP;

        inj = try allocator.create(Injection);
        inj.* = Injection{
            .allocator = allocator,
            .mode = M_VAL,
            .key = S_DTOP,
            .val = val,
            .parent = parent_val,
            .base = S_DTOP,
            .dparent = store,
            .keys = init_keys,
            .path = init_path,
            .nodes = init_nodes,
            .dpath = init_dpath,
            .errs = errs,
        };

        // Merge in partial init if provided.
        if (inj_opt) |existing| {
            if (existing.dparent != .null) inj.dparent = existing.dparent;
            if (existing.dpath.len > 0) inj.dpath = existing.dpath;
            if (existing.modify != null) inj.modify = existing.modify;
            if (existing.meta != .null) inj.meta = existing.meta;
            if (existing.validate_mode) inj.validate_mode = true;
            if (existing.exact_mode) inj.exact_mode = true;
        }
    } else {
        inj = inj_opt.?;
    }

    inj.descend();
    var current = val;

    if (isnode(val)) {
        // Get sorted keys: normal first, then $ transform keys.
        var normal_keys = std.ArrayList([]const u8).init(allocator);
        var transform_keys = std.ArrayList([]const u8).init(allocator);

        const all_keys = try keysof(allocator, current);
        if (all_keys == .array) {
            for (all_keys.array.data.items) |k| {
                if (k != .string) continue;
                const ks = k.string;
                if (std.mem.indexOf(u8, ks, S_DS) != null) {
                    try transform_keys.append(ks);
                } else {
                    try normal_keys.append(ks);
                }
            }
        }

        var node_keys = std.ArrayList([]const u8).init(allocator);
        for (normal_keys.items) |k| try node_keys.append(k);
        for (transform_keys.items) |k| try node_keys.append(k);

        var nkI: usize = 0;
        while (nkI < node_keys.items.len) {
            const nodekey = node_keys.items[nkI];

            var childinj = try inj.child(nkI, node_keys.items);
            childinj.mode = M_KEYPRE;

            // Phase 1: KEYPRE — inject the key string.
            const pre_key = try injectStr(allocator, nodekey, store, childinj);

            // Injection may modify child processing state.
            nkI = childinj.key_i;
            node_keys = blk: {
                var nk = std.ArrayList([]const u8).init(allocator);
                for (childinj.keys) |k| try nk.append(k);
                break :blk nk;
            };
            current = childinj.parent;

            if (pre_key != .null) {
                const prekey_str = if (pre_key == .string) pre_key.string else nodekey;
                const childval = try getprop(allocator, current, JsonValue{ .string = prekey_str }, .null);
                childinj.val = childval;
                childinj.mode = M_VAL;

                // Phase 2: VAL — inject the child value.
                _ = try injectVal(allocator, childval, store, childinj);

                nkI = childinj.key_i;
                node_keys = blk: {
                    var nk = std.ArrayList([]const u8).init(allocator);
                    for (childinj.keys) |k| try nk.append(k);
                    break :blk nk;
                };
                current = childinj.parent;

                // Phase 3: KEYPOST — post-process the key.
                childinj.mode = M_KEYPOST;
                _ = try injectStr(allocator, nodekey, store, childinj);

                nkI = childinj.key_i;
                node_keys = blk: {
                    var nk = std.ArrayList([]const u8).init(allocator);
                    for (childinj.keys) |k| try nk.append(k);
                    break :blk nk;
                };
                current = childinj.parent;
            }

            nkI += 1;
        }
    } else if (val == .string) {
        // Inject paths into string scalars.
        inj.mode = M_VAL;
        const result = try injectStr(allocator, val.string, store, inj);
        if (!inj.skip and (result != .null or val != .null)) {
            _ = try inj.setval(result, 0);
        }
        inj.skip = false;
        current = result;
    }

    inj.val = current;

    // Call modify callback if set (skip suppresses modify too).
    if (!inj.skip) {
        if (inj.modify) |modify_fn| {
            const mval = getprop(allocator, inj.parent, JsonValue{ .string = inj.key }, .null) catch .null;
            modify_fn(allocator, mval, inj.key, inj.parent, inj, store);
        }
    }

    // Return value is the top-level result.
    return try getprop(allocator, inj.parent, JsonValue{ .string = S_DTOP }, .null);
}

// ============================================================================
// injectStr — resolve backtick path references using the Injection context.
// ============================================================================

fn injectStr(allocator: Allocator, val: []const u8, store: JsonValue, inj: *Injection) !JsonValue {
    if (val.len == 0) return JsonValue{ .string = S_MT };

    // Full injection: entire string is `path` (possibly with trailing digits).
    if (val.len >= 2 and val[0] == '`' and val[val.len - 1] == '`') {
        var inner_bt: usize = 0;
        for (val[1 .. val.len - 1]) |c| {
            if (c == '`') inner_bt += 1;
        }
        if (inner_bt == 0) {
            inj.full = true;
            var pathref = val[1 .. val.len - 1];
            pathref = stripCmdDigits(pathref);
            pathref = resolveSpecialEscapes(allocator, pathref);
            return try resolvePathOrCmd(allocator, pathref, store, inj);
        }
    }

    // No backticks → return as-is.
    if (std.mem.indexOf(u8, val, "`") == null) {
        return JsonValue{ .string = val };
    }

    // Partial injection: replace each `ref` segment.
    inj.full = false;
    var result = std.ArrayList(u8).init(allocator);
    var i: usize = 0;
    while (i < val.len) {
        if (val[i] == '`') {
            const close = std.mem.indexOfScalarPos(u8, val, i + 1, '`');
            if (close) |end| {
                var ref = val[i + 1 .. end];
                ref = resolveSpecialEscapes(allocator, ref);
                const found = try resolvePathOnly(allocator, ref, store, inj);
                if (found == .string) {
                    try result.appendSlice(found.string);
                } else if (found == .null) {
                    // Check if the key actually exists in the store with a null value
                    // vs being absent. If present, stringify as "null".
                    const exists = blk: {
                        if (store == .object) {
                            if (store.object.get(ref) != null) break :blk true;
                            // Check in $TOP
                            if (store.object.get(S_DTOP)) |top| {
                                if (top == .object and top.object.get(ref) != null) break :blk true;
                            }
                        }
                        break :blk false;
                    };
                    if (exists) try result.appendSlice("null");
                } else if (isnode(found)) {
                    // Nodes use compact JSON format in partial injections.
                    try result.appendSlice(try jsonifyCompact(allocator, found));
                } else {
                    try result.appendSlice(try stringifyInner(allocator, found));
                }
                i = end + 1;
            } else {
                try result.append(val[i]);
                i += 1;
            }
        } else {
            try result.append(val[i]);
            i += 1;
        }
    }
    return JsonValue{ .string = result.items };
}

// Resolve a path reference that may be a command or a data path.
fn resolvePathOrCmd(allocator: Allocator, pathref: []const u8, store: JsonValue, inj: *Injection) !JsonValue {
    // Built-in escape commands (always resolve regardless of mode).
    if (std.mem.eql(u8, pathref, "$BT")) return JsonValue{ .string = S_BT };
    if (std.mem.eql(u8, pathref, "$DS")) return JsonValue{ .string = S_DS };

    // Command dispatch — mode-sensitive.
    if (pathref.len > 0 and pathref[0] == '$') {
        return try dispatchCmd(allocator, pathref, store, inj);
    }

    // Relative path — use getpathInj so ancestor traversal uses dpath.
    if (pathref.len > 0 and pathref[0] == '.') {
        return try getpathInj(allocator, JsonValue{ .string = pathref }, store, inj);
    }

    // Absolute path from store.
    return try getpath(allocator, JsonValue{ .string = pathref }, store);
}

// Resolve a path reference (no command dispatch — used for partial injections).
fn resolvePathOnly(allocator: Allocator, pathref: []const u8, store: JsonValue, inj: *Injection) !JsonValue {
    if (std.mem.eql(u8, pathref, "$BT")) return JsonValue{ .string = S_BT };
    if (std.mem.eql(u8, pathref, "$DS")) return JsonValue{ .string = S_DS };

    if (pathref.len > 0 and pathref[0] == '.') {
        return try getpathInj(allocator, JsonValue{ .string = pathref }, store, inj);
    }

    return try getpath(allocator, JsonValue{ .string = pathref }, store);
}

fn resolveRelativePath(allocator: Allocator, pathref: []const u8, dparent: JsonValue) anyerror!JsonValue {
    var dots: usize = 0;
    while (dots < pathref.len and pathref[dots] == '.') dots += 1;

    const rest = pathref[dots..];
    if (rest.len == 0) return dparent;

    var val = dparent;
    var it = std.mem.splitScalar(u8, rest, '.');
    while (it.next()) |part| {
        if (val == .null) break;
        val = try getprop(allocator, val, JsonValue{ .string = part }, .null);
    }
    return val;
}

// ============================================================================
// Command dispatch — routes $ commands to handlers based on mode.
// ============================================================================

fn dispatchCmd(allocator: Allocator, cmd: []const u8, store: JsonValue, inj: *Injection) !JsonValue {
    if (std.mem.eql(u8, cmd, "$COPY")) return cmdCopy(allocator, inj);
    if (std.mem.eql(u8, cmd, "$DELETE")) return cmdDelete(inj);
    if (std.mem.eql(u8, cmd, "$KEY")) return cmdKey(inj);
    if (std.mem.eql(u8, cmd, "$MERGE")) return try cmdMerge(allocator, inj, store);
    if (std.mem.eql(u8, cmd, "$ANNO")) return cmdAnno(inj);
    if (std.mem.eql(u8, cmd, "$FORMAT")) return try cmdFormat(allocator, inj, store);
    if (std.mem.eql(u8, cmd, "$EACH")) return try cmdEach(allocator, inj, store);
    if (std.mem.eql(u8, cmd, "$PACK")) return try cmdPack(allocator, inj, store);
    if (std.mem.eql(u8, cmd, "$REF")) return try cmdRef(allocator, inj, store);
    if (std.mem.eql(u8, cmd, "$APPLY")) return try cmdApply(allocator, inj);

    // Validation commands — only active when validate_mode is set.
    if (inj.validate_mode) {
        if (std.mem.eql(u8, cmd, "$STRING")) return try cmdValidateType(allocator, inj, S_string, T_string);
        if (std.mem.eql(u8, cmd, "$NUMBER")) return try cmdValidateType(allocator, inj, S_number, T_number);
        if (std.mem.eql(u8, cmd, "$INTEGER")) return try cmdValidateType(allocator, inj, S_integer, T_integer);
        if (std.mem.eql(u8, cmd, "$DECIMAL")) return try cmdValidateType(allocator, inj, S_decimal, T_decimal);
        if (std.mem.eql(u8, cmd, "$BOOLEAN")) return try cmdValidateType(allocator, inj, S_boolean, T_boolean);
        if (std.mem.eql(u8, cmd, "$NULL")) return try cmdValidateType(allocator, inj, S_null, T_null);
        if (std.mem.eql(u8, cmd, "$OBJECT") or std.mem.eql(u8, cmd, "$MAP"))
            return try cmdValidateType(allocator, inj, S_map, T_map);
        if (std.mem.eql(u8, cmd, "$ARRAY") or std.mem.eql(u8, cmd, "$LIST"))
            return try cmdValidateType(allocator, inj, S_list, T_list);
        if (std.mem.eql(u8, cmd, "$ANY")) return cmdValidateAny(inj);
        if (std.mem.eql(u8, cmd, "$ONE")) return try cmdValidateOne(allocator, inj, store);
        if (std.mem.eql(u8, cmd, "$EXACT")) return try cmdValidateExactCmd(allocator, inj);
        if (std.mem.eql(u8, cmd, "$CHILD")) return try cmdValidateChildCmd(allocator, inj, store);
    }

    // Unknown $ key — check if the store has it as a function value.
    if (store == .object) {
        if (store.object.get(cmd)) |val| {
            if (val == .function) {
                return try val.function(allocator);
            }
            return val;
        }
    }
    return .null;
}

fn cmdCopy(allocator: Allocator, inj: *Injection) JsonValue {
    if (inj.mode != M_VAL) return .null;
    const out = getprop(allocator, inj.dparent, JsonValue{ .string = inj.key }, .null) catch .null;
    _ = inj.setval(out, 0) catch {};
    return out;
}

fn cmdDelete(inj: *Injection) JsonValue {
    _ = inj.setval(.null, 0) catch {};
    return .null;
}

fn cmdKey(inj: *Injection) JsonValue {
    if (inj.mode != M_VAL) return .null;
    if (inj.parent == .object) {
        if (inj.parent.object.get(S_BKEY)) |keyspec| {
            _ = inj.parent.object.fetchOrderedRemove(S_BKEY);
            return getprop(inj.allocator, inj.dparent, keyspec, .null) catch .null;
        }
        if (inj.parent.object.get(S_BANNO)) |anno| {
            if (anno == .object) {
                if (anno.object.get(S_KEY)) |pkey| return pkey;
            }
        }
    }
    if (inj.path.len >= 2) return JsonValue{ .string = inj.path[inj.path.len - 2] };
    return .null;
}

fn cmdMerge(allocator: Allocator, inj: *Injection, store: JsonValue) !JsonValue {
    if (inj.mode == M_KEYPRE) return JsonValue{ .string = inj.key };

    if (inj.mode == M_KEYPOST) {
        const args = try getprop(allocator, inj.parent, JsonValue{ .string = inj.key }, .null);

        // Remove $MERGE key from parent first.
        if (inj.parent == .object) _ = inj.parent.object.fetchOrderedRemove(inj.key);

        // Clone parent AFTER removing (Go does Clone(inj.Parent) post-remove).
        // With *MapRef, the clone reads from the same pointer data.
        const parent_clone = try clone(allocator, inj.parent);

        const merge_list_lr = try allocator.create(ListRef);
        merge_list_lr.* = .{ .data = ListData.init(allocator) };
        const merge_list = merge_list_lr;
        try merge_list.append(inj.parent);

        if (args == .string and args.string.len == 0) {
            const top = getpropFromStore(store);
            if (top != .null) try merge_list.append(try clone(allocator, top));
        } else if (args == .array) {
            for (args.array.data.items) |item| {
                if (item != .null) try merge_list.append(item);
            }
        } else if (args != .null) {
            try merge_list.append(args);
        }

        // Literals in parent have precedence.
        try merge_list.append(parent_clone);
        const merged = try merge(allocator, JsonValue{ .array = merge_list }, MAXDEPTH);

        // Copy merge result INTO the existing *MapRef to preserve pointer identity.
        // Go's Merge modifies the first element in place; outer references see changes.
        if (merged == .object and inj.parent == .object) {
            // Clear existing entries and copy from merged result.
            const parent_map = inj.parent.object;
            // Remove all existing keys.
            const existing_keys = try keysof(allocator, inj.parent);
            if (existing_keys == .array) {
                for (existing_keys.array.data.items) |k| {
                    if (k == .string) _ = parent_map.fetchOrderedRemove(k.string);
                }
            }
            // Copy in merged entries.
            var it = merged.object.iterator();
            while (it.next()) |kv| {
                try parent_map.put(kv.key_ptr.*, kv.value_ptr.*);
            }
        } else {
            inj.parent = merged;
        }
        return JsonValue{ .string = inj.key };
    }

    return .null;
}

fn cmdAnno(inj: *Injection) JsonValue {
    if (inj.parent == .object) _ = inj.parent.object.fetchOrderedRemove(S_BANNO);
    return .null;
}

// ============================================================================
// Validation commands — fire inside the injection pipeline when validate_mode.
// ============================================================================

fn cmdValidateType(allocator: Allocator, inj: *Injection, tname: []const u8, tbit: i32) anyerror!JsonValue {
    if (inj.mode != M_VAL) return .null;
    const out = getprop(allocator, inj.dparent, JsonValue{ .string = inj.key }, .null) catch .null;
    const t = typify(out);

    // $STRING: also reject empty strings.
    if (tbit == T_string) {
        if (0 == (@as(i64, T_string) & t)) {
            try inj.errs.append(try invalidTypeMsg(allocator, inj.path, tname, out));
            return .null;
        }
        if (out == .string and out.string.len == 0) {
            try inj.errs.append(try std.fmt.allocPrint(allocator, "Empty string at {s}", .{try pathifySlice(allocator, inj.path[1..])}));
            return .null;
        }
        _ = try inj.setval(out, 0);
        return out;
    }

    if (0 == (@as(i64, tbit) & t)) {
        try inj.errs.append(try invalidTypeMsg(allocator, inj.path, tname, out));
        return .null;
    }
    _ = try inj.setval(out, 0);
    return out;
}

fn cmdValidateAny(inj: *Injection) JsonValue {
    if (inj.mode != M_VAL) return .null;
    const out = getprop(inj.allocator, inj.dparent, JsonValue{ .string = inj.key }, .null) catch .null;
    _ = inj.setval(out, 0) catch {};
    return out;
}

fn cmdValidateOne(allocator: Allocator, inj: *Injection, _: JsonValue) anyerror!JsonValue {
    if (inj.mode != M_VAL) return .null;
    if (inj.parent != .array) return .null;

    // Skip remaining keys in the list.
    inj.key_i = inj.keys.len;

    const parent_items = inj.parent.array.data.items;
    if (parent_items.len < 2) return .null;

    // Get data value at this position.
    const data_val = getprop(allocator, inj.dparent, JsonValue{ .string = inj.key }, .null) catch inj.dparent;

    // Replace [$ONE, alt0, alt1, ...] with the data value in the grandparent.
    _ = try inj.setval(data_val, 2);

    // Try each alternative.
    const alts = parent_items[1..];
    for (alts) |alt| {
        const terrs = std.ArrayList([]const u8).init(allocator);
        const terrs_ptr = try allocator.create(std.ArrayList([]const u8));
        terrs_ptr.* = terrs;
        _ = try validateWalk(allocator, alt, data_val, terrs_ptr, if (inj.path.len > 1) inj.path[1..] else inj.path);
        if (terrs_ptr.items.len == 0) return .null;
    }

    // No match — build error message.
    var desc = std.ArrayList(u8).init(allocator);
    for (alts, 0..) |alt, i| {
        if (i > 0) try desc.appendSlice(", ");
        try desc.appendSlice(try stringify(allocator, alt, null));
    }
    const prefix = if (alts.len > 1) "one of " else "";
    try inj.errs.append(try invalidTypeMsg(allocator, inj.path, try std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, desc.items }), data_val));
    return .null;
}

fn cmdValidateExactCmd(allocator: Allocator, inj: *Injection) anyerror!JsonValue {
    if (inj.mode != M_VAL) return .null;
    if (inj.parent != .array) return .null;

    inj.key_i = inj.keys.len;

    const parent_items = inj.parent.array.data.items;
    if (parent_items.len < 2) return .null;

    const data_val = getprop(allocator, inj.dparent, JsonValue{ .string = inj.key }, .null) catch inj.dparent;
    _ = try inj.setval(data_val, 2);

    const alts = parent_items[1..];
    for (alts) |alt| {
        const a = try toStdJson(allocator, alt);
        const b = try toStdJson(allocator, data_val);
        if (stdJsonEqual(a, b)) return .null;
        // Also try string comparison.
        const sa = try stringify(allocator, alt, null);
        const sb = try stringify(allocator, data_val, null);
        if (std.mem.eql(u8, sa, sb)) return .null;
    }

    var desc = std.ArrayList(u8).init(allocator);
    for (alts, 0..) |alt, i| {
        if (i > 0) try desc.appendSlice(", ");
        try desc.appendSlice(try stringify(allocator, alt, null));
    }
    const prefix = if (alts.len > 1) "one of " else "";
    try inj.errs.append(try invalidTypeMsg(allocator, inj.path, try std.fmt.allocPrint(allocator, "exactly equal to {s}{s}", .{ prefix, desc.items }), data_val));
    return .null;
}

fn cmdValidateChildCmd(allocator: Allocator, inj: *Injection, store: JsonValue) anyerror!JsonValue {
    _ = store;
    if (inj.mode == M_KEYPRE and inj.parent == .object) {
        // Map mode: expand $CHILD for each key in the data.
        const child = getprop(allocator, inj.parent, JsonValue{ .string = inj.key }, .null) catch .null;
        const pkey = if (inj.path.len >= 2) inj.path[inj.path.len - 2] else S_DTOP;
        const tval = getprop(allocator, inj.dparent, JsonValue{ .string = pkey }, .null) catch .null;

        if (tval == .object) {
            // For each key in data, clone the child spec into the parent.
            const ckeys = try keysof(allocator, tval);
            if (ckeys == .array) {
                for (ckeys.array.data.items) |ck| {
                    if (ck == .string) {
                        try inj.parent.object.put(ck.string, try clone(allocator, child));
                        // Append to keys for further processing.
                        inj.keys = appendSlice(allocator, []const u8, inj.keys, ck.string) catch inj.keys;
                    }
                }
            }
        } else if (tval != .null) {
            try inj.errs.append(try invalidTypeMsg(allocator, if (inj.path.len > 1) inj.path[0 .. inj.path.len - 1] else inj.path, S_object, tval));
        }

        // Remove the $CHILD key.
        _ = inj.parent.object.fetchOrderedRemove(inj.key);
        return .null;
    }

    if (inj.mode == M_VAL and inj.parent == .array) {
        // List mode: [$CHILD, template] — expand for each element.
        if (inj.parent.array.data.items.len < 2) return .null;
        const child = inj.parent.array.data.items[1];
        const dparent_val = inj.dparent;

        if (dparent_val == .null) {
            inj.parent.array.data.items.len = 0;
            return .null;
        }

        if (dparent_val != .array) {
            try inj.errs.append(try invalidTypeMsg(allocator, if (inj.path.len > 1) inj.path[0 .. inj.path.len - 1] else inj.path, S_list, dparent_val));
            return dparent_val;
        }

        const dlen = dparent_val.array.data.items.len;
        inj.parent.array.data.items.len = 0;
        var li: usize = 0;
        while (li < dlen) : (li += 1) {
            try inj.parent.array.append(try clone(allocator, child));
        }
        inj.key_i = 0;
        return if (dlen > 0) dparent_val.array.data.items[0] else .null;
    }

    return .null;
}

// ============================================================================
// $FORMAT — apply a named formatter to a child value.
// Format: ["`$FORMAT`", "name", child]
// ============================================================================

fn cmdFormat(allocator: Allocator, inj: *Injection, store: JsonValue) !JsonValue {
    if (inj.mode != M_VAL) return .null;
    if (inj.keys.len > 1) inj.keys = inj.keys[0..1];

    if (inj.parent != .array or inj.parent.array.data.items.len < 3) return .null;
    const name_val = inj.parent.array.data.items[1];
    const child_raw = inj.parent.array.data.items[2];

    const name = if (name_val == .string) name_val.string else "";

    // Inject the child value first (resolve $COPY etc).
    const child = try injectChild(allocator, child_raw, store, inj);

    // Find target node and key.
    const tkey = if (inj.path.len >= 2) inj.path[inj.path.len - 2] else S_DTOP;
    const target = if (inj.nodes.len >= 2)
        inj.nodes[inj.nodes.len - 2]
    else if (inj.nodes.len > 0)
        inj.nodes[inj.nodes.len - 1]
    else
        JsonValue{ .null = {} };

    const out = try applyFormat(allocator, name, child, inj.errs);
    if (out == .null and !std.mem.eql(u8, name, "identity")) {
        // Unknown format or error → delete from target.
        if (target != .null) _ = delprop(allocator, target, JsonValue{ .string = tkey }) catch {};
        return .null;
    }

    if (target != .null) _ = setprop(allocator, target, JsonValue{ .string = tkey }, out) catch {};
    return out;
}

fn applyFormat(allocator: Allocator, name: []const u8, val: JsonValue, errs: *std.ArrayList([]const u8)) !JsonValue {
    if (std.mem.eql(u8, name, "upper")) return try walkFormat(allocator, val, fmtUpper);
    if (std.mem.eql(u8, name, "lower")) return try walkFormat(allocator, val, fmtLower);
    if (std.mem.eql(u8, name, "string")) return try walkFormat(allocator, val, fmtString);
    if (std.mem.eql(u8, name, "number")) return try walkFormat(allocator, val, fmtNumber);
    if (std.mem.eql(u8, name, "integer")) return try walkFormat(allocator, val, fmtInteger);
    if (std.mem.eql(u8, name, "identity")) return val;
    if (std.mem.eql(u8, name, "concat")) {
        if (val == .array) {
            var buf = std.ArrayList(u8).init(allocator);
            for (val.array.data.items) |item| {
                if (isnode(item)) continue;
                try buf.appendSlice(try fmtStr(allocator, item));
            }
            return JsonValue{ .string = buf.items };
        }
        return val;
    }
    const msg = try std.fmt.allocPrint(allocator, "$FORMAT: unknown format: {s}.", .{name});
    try errs.append(msg);
    return .null;
}

const FormatFn = *const fn (Allocator, JsonValue) anyerror!JsonValue;

fn walkFormat(allocator: Allocator, val: JsonValue, fmt_fn: FormatFn) !JsonValue {
    if (val == .object) {
        const new_obj = try allocator.create(MapRef);
        new_obj.* = .{ .data = MapData.init(allocator) };
        var it = val.object.iterator();
        while (it.next()) |kv| {
            try new_obj.put(kv.key_ptr.*, try walkFormat(allocator, kv.value_ptr.*, fmt_fn));
        }
        return JsonValue{ .object = new_obj };
    }
    if (val == .array) {
        const new_arr_lr = try allocator.create(ListRef);
        new_arr_lr.* = .{ .data = try ListData.initCapacity(allocator, val.array.data.items.len) };
        const new_arr = new_arr_lr;
        for (val.array.data.items) |item| {
            try new_arr.append(try walkFormat(allocator, item, fmt_fn));
        }
        return JsonValue{ .array = new_arr };
    }
    return try fmt_fn(allocator, val);
}

fn fmtStr(allocator: Allocator, val: JsonValue) ![]const u8 {
    return switch (val) {
        .null => "null",
        .bool => |b| if (b) "true" else "false",
        .string => |s| s,
        .integer => |i| try std.fmt.allocPrint(allocator, "{d}", .{i}),
        .float => |f| try std.fmt.allocPrint(allocator, "{d}", .{f}),
        else => "",
    };
}

fn fmtUpper(allocator: Allocator, val: JsonValue) !JsonValue {
    const s = try fmtStr(allocator, val);
    var buf = try allocator.alloc(u8, s.len);
    for (s, 0..) |c, i| buf[i] = std.ascii.toUpper(c);
    return JsonValue{ .string = buf };
}

fn fmtLower(allocator: Allocator, val: JsonValue) !JsonValue {
    const s = try fmtStr(allocator, val);
    var buf = try allocator.alloc(u8, s.len);
    for (s, 0..) |c, i| buf[i] = std.ascii.toLower(c);
    return JsonValue{ .string = buf };
}

fn fmtString(allocator: Allocator, val: JsonValue) !JsonValue {
    return JsonValue{ .string = try fmtStr(allocator, val) };
}

fn fmtNumber(allocator: Allocator, val: JsonValue) !JsonValue {
    _ = allocator;
    return switch (val) {
        .integer => val,
        .float => val,
        .string => |s| {
            if (std.fmt.parseFloat(f64, s)) |f| {
                if (f == @trunc(f)) return JsonValue{ .integer = @intFromFloat(f) };
                return JsonValue{ .float = f };
            } else |_| return JsonValue{ .integer = 0 };
        },
        else => JsonValue{ .integer = 0 },
    };
}

fn fmtInteger(allocator: Allocator, val: JsonValue) !JsonValue {
    _ = allocator;
    return switch (val) {
        .integer => val,
        .float => |f| JsonValue{ .integer = @intFromFloat(@trunc(f)) },
        .string => |s| {
            if (std.fmt.parseFloat(f64, s)) |f| {
                return JsonValue{ .integer = @intFromFloat(@trunc(f)) };
            } else |_| return JsonValue{ .integer = 0 };
        },
        else => JsonValue{ .integer = 0 },
    };
}

// ============================================================================
// $EACH — iterate source data, apply child template per item.
// Format: ["`$EACH`", "source-path", child-template]
// ============================================================================

fn cmdEach(allocator: Allocator, inj: *Injection, store: JsonValue) !JsonValue {
    if (inj.mode != M_VAL) return .null;
    if (inj.keys.len > 1) inj.keys = inj.keys[0..1];

    if (inj.parent != .array or inj.parent.array.data.items.len < 3) return .null;
    const srcpath_val = inj.parent.array.data.items[1];
    const child_tmpl = inj.parent.array.data.items[2];

    const srcpath = if (srcpath_val == .string) srcpath_val.string else "";

    // Resolve source data.
    const src = if (srcpath.len == 0)
        getpropFromStore(store)
    else
        try getpath(allocator, JsonValue{ .string = srcpath }, store);

    // Find target node and key.
    const tkey = if (inj.path.len >= 2) inj.path[inj.path.len - 2] else S_DTOP;
    const target = if (inj.nodes.len >= 2)
        inj.nodes[inj.nodes.len - 2]
    else if (inj.nodes.len > 0)
        inj.nodes[inj.nodes.len - 1]
    else
        JsonValue{ .null = {} };

    // Build source value list and key list.
    var src_vals = std.ArrayList(JsonValue).init(allocator);
    var src_keys = std.ArrayList([]const u8).init(allocator);
    var tval_items = std.ArrayList(JsonValue).init(allocator);

    if (islist(src)) {
        for (src.array.data.items, 0..) |src_item, idx| {
            try src_vals.append(src_item);
            try src_keys.append(try std.fmt.allocPrint(allocator, "{d}", .{idx}));
            try tval_items.append(try clone(allocator, child_tmpl));
        }
    } else if (ismap(src)) {
        const src_items = try items(allocator, src);
        if (src_items == .array) {
            for (src_items.array.data.items) |pair| {
                if (pair != .array or pair.array.data.items.len < 2) continue;
                const sk = if (pair.array.data.items[0] == .string) pair.array.data.items[0].string else "";
                try src_vals.append(pair.array.data.items[1]);
                try src_keys.append(sk);
                const cclone = try clone(allocator, child_tmpl);
                // Add $ANNO with $KEY for map sources.
                if (cclone == .object) {
                    const anno = try allocator.create(MapRef);
                    anno.* = .{ .data = MapData.init(allocator) };
                    try anno.put(S_KEY, pair.array.data.items[0]);
                    _ = try setprop(allocator, cclone, JsonValue{ .string = S_BANNO }, JsonValue{ .object = anno });
                }
                try tval_items.append(cclone);
            }
        }
    }

    // Build result by injecting each template individually with per-item context.
    const result_lr = try allocator.create(ListRef);
    result_lr.* = .{ .data = ListData.init(allocator) };

    for (src_vals.items, 0..) |src_item, idx| {
        const child_clone = tval_items.items[idx];

        // Build per-item store: original store + $TOP = src_item.
        // Also merge root data keys for ancestor path access.
        const each_store = try allocator.create(MapRef);
        each_store.* = .{ .data = MapData.init(allocator) };
        if (store == .object) {
            var sit = store.object.iterator();
            while (sit.next()) |kv| try each_store.put(kv.key_ptr.*, kv.value_ptr.*);
        }
        const root_data = getpropFromStore(store);
        if (root_data == .object) {
            var rit = root_data.object.iterator();
            while (rit.next()) |rkv| {
                if (each_store.get(rkv.key_ptr.*) == null)
                    try each_store.put(rkv.key_ptr.*, rkv.value_ptr.*);
            }
        }
        try each_store.put(S_DTOP, src_item);

        const injected = try injectVal(allocator, child_clone, JsonValue{ .object = each_store }, null);
        try result_lr.append(injected);
    }

    const result = JsonValue{ .array = result_lr };
    if (target != .null) _ = setprop(allocator, target, JsonValue{ .string = tkey }, result) catch {};

    if (result_lr.data.items.len > 0) return result_lr.data.items[0];
    return .null;
}

// ============================================================================
// $PACK — convert source list/map to keyed map.
// Format: map key `$PACK` with value ["source-path", child-spec]
// ============================================================================

fn cmdPack(allocator: Allocator, inj: *Injection, store: JsonValue) !JsonValue {
    if (inj.mode != M_KEYPRE) return .null;

    if (inj.parent != .object) return .null;
    const args_val = try getprop(allocator, inj.parent, JsonValue{ .string = inj.key }, .null);
    if (args_val != .array or args_val.array.data.items.len < 2) return .null;

    const srcpath_val = args_val.array.data.items[0];
    const childspec_raw = args_val.array.data.items[1];

    const srcpath = if (srcpath_val == .string) srcpath_val.string else "";

    // Resolve source data.
    const src_raw = if (srcpath.len == 0)
        getpropFromStore(store)
    else
        try getpath(allocator, JsonValue{ .string = srcpath }, store);

    // Normalize source to list.
    var src_list = std.ArrayList(JsonValue).init(allocator);
    var src_keys = std.ArrayList([]const u8).init(allocator);
    var src_is_map = false;

    if (islist(src_raw)) {
        for (src_raw.array.data.items, 0..) |item, idx| {
            try src_list.append(item);
            try src_keys.append(try std.fmt.allocPrint(allocator, "{d}", .{idx}));
        }
    } else if (ismap(src_raw)) {
        src_is_map = true;
        const src_items = try items(allocator, src_raw);
        if (src_items == .array) {
            for (src_items.array.data.items) |pair| {
                if (pair != .array or pair.array.data.items.len < 2) continue;
                const k = if (pair.array.data.items[0] == .string) pair.array.data.items[0].string else "";
                try src_list.append(pair.array.data.items[1]);
                try src_keys.append(k);
            }
        }
    } else return .null;

    // Extract $KEY path and $VAL from child spec.
    var childspec = try clone(allocator, childspec_raw);
    var keypath: ?[]const u8 = null;
    var child_val_spec = childspec;

    if (childspec == .object) {
        if (childspec.object.get(S_BKEY)) |kp| {
            if (kp == .string) keypath = kp.string;
            _ = childspec.object.fetchOrderedRemove(S_BKEY);
        }
        if (childspec.object.get(S_BVAL)) |vspec| {
            child_val_spec = vspec;
            _ = childspec.object.fetchOrderedRemove(S_BVAL);
        }
    }

    // Find target.
    const tkey = if (inj.path.len >= 2) inj.path[inj.path.len - 2] else S_DTOP;
    const target = if (inj.nodes.len >= 2)
        inj.nodes[inj.nodes.len - 2]
    else if (inj.nodes.len > 0)
        inj.nodes[inj.nodes.len - 1]
    else
        JsonValue{ .null = {} };

    // Build the output map.
    const result_obj = try allocator.create(MapRef);
        result_obj.* = .{ .data = MapData.init(allocator) };
    for (src_list.items, 0..) |src_item, idx| {
        // Resolve the key for this item.
        var item_key: []const u8 = "";
        if (keypath) |kp| {
            // Key from source item field or injection.
            if (std.mem.startsWith(u8, kp, "`")) {
                // Backtick path: inject to resolve.
                const key_store = try allocator.create(MapRef);
        key_store.* = .{ .data = MapData.init(allocator) };
                if (store == .object) {
                    var sit = store.object.iterator();
                    while (sit.next()) |kv| try key_store.put(kv.key_ptr.*, kv.value_ptr.*);
                }
                try key_store.put(S_DTOP, src_item);
                const key_result = try injectVal(allocator, JsonValue{ .string = kp }, JsonValue{ .object = key_store }, null);
                if (key_result == .string) item_key = key_result.string;
            } else {
                // Direct property path.
                const kval = try getpath(allocator, JsonValue{ .string = kp }, src_item);
                if (kval == .string) item_key = kval.string;
            }
        } else {
            item_key = try std.fmt.allocPrint(allocator, "{d}", .{idx});
        }
        if (item_key.len == 0) continue;

        // Clone the child template for this item.
        const child_clone = try clone(allocator, child_val_spec);

        // Build per-item store.
        const item_store = try allocator.create(MapRef);
        item_store.* = .{ .data = MapData.init(allocator) };
        if (store == .object) {
            var sit = store.object.iterator();
            while (sit.next()) |kv| try item_store.put(kv.key_ptr.*, kv.value_ptr.*);
        }
        try item_store.put(S_DTOP, src_item);

        // Add $ANNO with $KEY. For map sources, use the source map key
        // so `$KEY` in the template returns "a"/"b". For array sources,
        // use the resolved item_key (supports $KEY=$COPY → "a" not "0").
        if (child_clone == .object) {
            const anno = try allocator.create(MapRef);
            anno.* = .{ .data = MapData.init(allocator) };
            const anno_val = if (src_is_map)
                JsonValue{ .string = src_keys.items[idx] }
            else
                JsonValue{ .string = item_key };
            try anno.put(S_KEY, anno_val);
            _ = try setprop(allocator, child_clone, JsonValue{ .string = S_BANNO }, JsonValue{ .object = anno });
        }

        // Build dpath for ancestor path resolution using the ORIGINAL store,
        // so `...v100` can resolve back to the root data.
        var dpath_list = std.ArrayList([]const u8).init(allocator);
        try dpath_list.append(S_DTOP);
        if (srcpath.len > 0) {
            var spit = std.mem.splitScalar(u8, srcpath, '.');
            while (spit.next()) |sp| try dpath_list.append(sp);
        }
        try dpath_list.append(try std.fmt.allocPrint(allocator, "$:{s}", .{tkey}));
        if (inj.path.len > 3) {
            const pkey = if (inj.path.len >= 3) inj.path[inj.path.len - 3] else S_DTOP;
            try dpath_list.append(try std.fmt.allocPrint(allocator, "$:{s}", .{pkey}));
        }

        // Wrap: {tkey: {src_key: src_item}} so dparent descent works.
        const inner_wrap = try allocator.create(MapRef);
        inner_wrap.* = .{ .data = MapData.init(allocator) };
        try inner_wrap.put(src_keys.items[idx], src_item);
        const outer_wrap = try allocator.create(MapRef);
        outer_wrap.* = .{ .data = MapData.init(allocator) };
        try outer_wrap.put(tkey, JsonValue{ .object = inner_wrap });

        // Build per-item store: merge original root data keys into the
        // store alongside $TOP = src_item. This way `$COPY` gets the item
        // (via $TOP) and `...v100` can find v100 as a direct store key.
        const pack_store = try allocator.create(MapRef);
        pack_store.* = .{ .data = MapData.init(allocator) };
        if (store == .object) {
            var sit = store.object.iterator();
            while (sit.next()) |kv| try pack_store.put(kv.key_ptr.*, kv.value_ptr.*);
        }
        // Merge root data keys directly into store for ancestor access.
        const root_data = getpropFromStore(store);
        if (root_data == .object) {
            var rit = root_data.object.iterator();
            while (rit.next()) |rkv| {
                // Don't override existing store keys.
                if (pack_store.get(rkv.key_ptr.*) == null) {
                    try pack_store.put(rkv.key_ptr.*, rkv.value_ptr.*);
                }
            }
        }
        try pack_store.put(S_DTOP, src_item);

        const injected = try injectVal(allocator, child_clone, JsonValue{ .object = pack_store }, null);
        try result_obj.put(item_key, injected);
    }

    const result = JsonValue{ .object = result_obj };

    // Remove the $PACK key from parent and set result on target.
    if (inj.parent == .object) _ = inj.parent.object.fetchOrderedRemove(inj.key);
    if (target != .null) _ = setprop(allocator, target, JsonValue{ .string = tkey }, result) catch {};

    return .null; // Drop the transform key.
}

// ============================================================================
// $REF — reference another spec path (enables recursive templates).
// Format: ["`$REF`", "spec-path"]
// ============================================================================

fn cmdRef(allocator: Allocator, inj: *Injection, store: JsonValue) !JsonValue {
    if (inj.mode != M_VAL) return .null;

    if (inj.parent != .array or inj.parent.array.data.items.len < 2) return .null;
    const refpath_val = inj.parent.array.data.items[1];
    if (refpath_val != .string) return .null;
    const refpath = refpath_val.string;

    // Skip remaining keys.
    inj.key_i = inj.keys.len;

    // Get the original spec from the store.
    const spec_val = if (store == .object) store.object.get(S_DSPEC) orelse .null else .null;
    if (spec_val == .null) return .null;

    // Resolve the ref path within the spec.
    const ref_result = try getpath(allocator, JsonValue{ .string = refpath }, spec_val);
    if (ref_result == .null) {
        // Ref not found → delete from parent.
        const tkey = if (inj.path.len >= 2) inj.path[inj.path.len - 2] else S_DTOP;
        const target = if (inj.nodes.len >= 2) inj.nodes[inj.nodes.len - 2] else .null;
        if (target != .null) _ = delprop(allocator, target, JsonValue{ .string = tkey }) catch {};
        return .null;
    }

    // Clone the referenced spec and inject it with proper data context.
    const tref = try clone(allocator, ref_result);

    // Compute paths following Go: tpath = path[:-1], cpath = path[:-3]
    const tpath = if (inj.path.len > 0) inj.path[0 .. inj.path.len - 1] else inj.path;
    const cpath = if (inj.path.len > 3) inj.path[0 .. inj.path.len - 3] else &[_][]const u8{};

    // Resolve data at these paths.
    const tcur = if (cpath.len > 0) blk: {
        var joined = std.ArrayList(u8).init(allocator);
        for (cpath, 0..) |p, pi| {
            if (pi > 0) try joined.append('.');
            try joined.appendSlice(p);
        }
        break :blk try getpath(allocator, JsonValue{ .string = joined.items }, store);
    } else store;

    // Build child injection with proper context.
    const lastPath = if (tpath.len > 0) tpath[tpath.len - 1] else S_DTOP;
    const tinj = try allocator.create(Injection);
    const tinj_nodes_src = if (inj.nodes.len > 1) inj.nodes[0 .. inj.nodes.len - 1] else inj.nodes[0..0];
    const tinj_nodes = try allocator.alloc(JsonValue, tinj_nodes_src.len);
    @memcpy(tinj_nodes, tinj_nodes_src);
    const tinj_dpath = try allocator.alloc([]const u8, cpath.len);
    @memcpy(tinj_dpath, cpath);
    tinj.* = Injection{
        .allocator = allocator,
        .mode = M_VAL,
        .key = lastPath,
        .val = tref,
        .parent = if (inj.nodes.len >= 2) inj.nodes[inj.nodes.len - 2] else .null,
        .base = inj.base,
        .dparent = tcur,
        .keys = try allocator.alloc([]const u8, 1),
        .path = tpath,
        .nodes = tinj_nodes,
        .dpath = tinj_dpath,
        .meta = inj.meta,
        .errs = inj.errs,
    };
    tinj.keys[0] = lastPath;

    _ = try injectVal(allocator, tref, store, tinj);
    const rval = tinj.val;

    // Set the result on the grandparent.
    _ = try inj.setval(rval, 2);

    // Adjust prior key index if grandparent is a list.
    if (inj.prior) |prior| {
        const gp = if (inj.nodes.len >= 2) inj.nodes[inj.nodes.len - 2] else .null;
        if (islist(gp)) {
            if (prior.key_i > 0) prior.key_i -= 1;
        }
    }

    return .null;
}

// ============================================================================
// $APPLY — apply a custom function (all tests are error cases).
// Format: ["`$APPLY`", function, child]
// ============================================================================

fn cmdApply(allocator: Allocator, inj: *Injection) !JsonValue {
    const ijname = "APPLY";

    if (inj.mode == M_KEYPRE) {
        const msg = try std.fmt.allocPrint(allocator, "${s}: invalid placement as key, expected: value.", .{ijname});
        try inj.errs.append(msg);
        return .null;
    }

    if (inj.mode == M_VAL) {
        // Check parent type — must be list.
        if (inj.parent != .array) {
            const msg = try std.fmt.allocPrint(allocator, "${s}: invalid placement in parent map, expected: list.", .{ijname});
            try inj.errs.append(msg);
            return .null;
        }

        // Check arguments.
        if (inj.parent.array.data.items.len >= 2) {
            const arg = inj.parent.array.data.items[1];
            // In Zig JSON, functions don't exist, so any non-function argument is an error.
            const arg_type = typify(arg);
            const arg_type_name = typename(arg_type);
            const arg_str = try stringify(allocator, arg, 22);
            const msg = try std.fmt.allocPrint(allocator, "${s}: invalid argument: {s} ({s} at position 1) is not of type: function.", .{ ijname, arg_str, arg_type_name });
            try inj.errs.append(msg);
        }

        // Delete from target.
        const tkey = if (inj.path.len >= 2) inj.path[inj.path.len - 2] else S_DTOP;
        const target = if (inj.nodes.len >= 2) inj.nodes[inj.nodes.len - 2] else .null;
        if (target != .null) _ = delprop(allocator, target, JsonValue{ .string = tkey }) catch {};
    }

    return .null;
}

// ============================================================================
// injectChild — inject a child value using the parent injection context.
// ============================================================================

fn injectChild(allocator: Allocator, child_raw: JsonValue, store: JsonValue, inj: *Injection) !JsonValue {
    // For simple cases: inject using the current context.
    var child_clone = try clone(allocator, child_raw);

    // Build store with correct data context.
    const child_store = try allocator.create(MapRef);
        child_store.* = .{ .data = MapData.init(allocator) };
    if (store == .object) {
        var sit = store.object.iterator();
        while (sit.next()) |kv| try child_store.put(kv.key_ptr.*, kv.value_ptr.*);
    }
    // Set $TOP to the data parent so $COPY works.
    child_store.put(S_DTOP, inj.dparent) catch {};

    child_clone = try injectVal(allocator, child_clone, JsonValue{ .object = child_store }, null);
    return child_clone;
}

// ============================================================================
// Transform — public API. Builds store and calls Inject.
// ============================================================================

pub fn transform(allocator: Allocator, data: JsonValue, spec: JsonValue) !JsonValue {
    if (spec == .null) return spec;

    const spec_clone = try clone(allocator, spec);
    const data_clone = if (data == .null) JsonValue{ .null = {} } else try clone(allocator, data);

    // Store the original spec for $REF.
    const orig_spec = try clone(allocator, spec);

    const store = try allocator.create(MapRef);
        store.* = .{ .data = MapData.init(allocator) };
    try store.put(S_DTOP, data_clone);
    try store.put(S_DSPEC, orig_spec);
    const store_val = JsonValue{ .object = store };

    return try injectVal(allocator, spec_clone, store_val, null);
}

// Transform with a modify callback applied after each injection step.
pub fn transformModify(allocator: Allocator, data: JsonValue, spec: JsonValue, modify: ?ModifyFn) !JsonValue {
    if (spec == .null) return spec;

    const spec_clone = try clone(allocator, spec);
    const data_clone = if (data == .null) JsonValue{ .null = {} } else try clone(allocator, data);
    const orig_spec = try clone(allocator, spec);

    const store = try allocator.create(MapRef);
    store.* = .{ .data = MapData.init(allocator) };
    try store.put(S_DTOP, data_clone);
    try store.put(S_DSPEC, orig_spec);
    const store_val = JsonValue{ .object = store };

    // Create a partial injection with modify set.
    const inj_init = try allocator.create(Injection);
    const empty_keys = try allocator.alloc([]const u8, 0);
    const empty_path = try allocator.alloc([]const u8, 0);
    const empty_nodes = try allocator.alloc(JsonValue, 0);
    const empty_dpath = try allocator.alloc([]const u8, 0);
    const errs = try allocator.create(std.ArrayList([]const u8));
    errs.* = std.ArrayList([]const u8).init(allocator);
    inj_init.* = Injection{
        .allocator = allocator,
        .mode = 0, // triggers root initialization in injectVal
        .modify = modify,
        .keys = empty_keys,
        .path = empty_path,
        .nodes = empty_nodes,
        .dpath = empty_dpath,
        .errs = errs,
    };

    return try injectVal(allocator, spec_clone, store_val, inj_init);
}

// ============================================================================
// Helpers retained from previous implementation.
// ============================================================================

fn stripCmdDigits(pathref: []const u8) []const u8 {
    if (pathref.len == 0 or pathref[0] != '$') return pathref;
    var end: usize = pathref.len;
    while (end > 1 and pathref[end - 1] >= '0' and pathref[end - 1] <= '9') end -= 1;
    return pathref[0..end];
}

fn resolveSpecialEscapes(allocator: Allocator, pathref: []const u8) []const u8 {
    if (pathref.len <= 3) return pathref;
    if (std.mem.indexOf(u8, pathref, "$BT") == null and
        std.mem.indexOf(u8, pathref, "$DS") == null) return pathref;
    var result = std.ArrayList(u8).init(allocator);
    var i: usize = 0;
    while (i < pathref.len) {
        if (i + 3 <= pathref.len and std.mem.eql(u8, pathref[i .. i + 3], "$BT")) {
            result.append('`') catch {};
            i += 3;
        } else if (i + 3 <= pathref.len and std.mem.eql(u8, pathref[i .. i + 3], "$DS")) {
            result.append('$') catch {};
            i += 3;
        } else {
            result.append(pathref[i]) catch {};
            i += 1;
        }
    }
    return result.items;
}

// (resolveRelativePath defined above near resolvePathOnly)

// ============================================================================
// Validate — check data against a spec, collecting type errors.
// Uses the transform/inject infrastructure with type-checking commands.
// ============================================================================

pub fn validate(allocator: Allocator, data: JsonValue, spec: JsonValue) anyerror!struct { out: JsonValue, err: ?[]const u8 } {
    const spec_clone = try clone(allocator, spec);
    const data_clone = if (data == .null) JsonValue{ .null = {} } else try clone(allocator, data);
    const orig_spec = try clone(allocator, spec);

    // Build store with data and spec.
    const store = try allocator.create(MapRef);
    store.* = .{ .data = MapData.init(allocator) };
    try store.put(S_DTOP, data_clone);
    try store.put(S_DSPEC, orig_spec);
    const store_val = JsonValue{ .object = store };

    // Create root injection with validate_mode enabled.
    // This causes dispatchCmd to handle $STRING, $NUMBER, etc.
    const errs = try allocator.create(std.ArrayList([]const u8));
    errs.* = std.ArrayList([]const u8).init(allocator);

    const inj_init = try allocator.create(Injection);
    inj_init.* = Injection{
        .allocator = allocator,
        .mode = 0, // triggers root init
        .validate_mode = true,
        .modify = validationModify,
        .keys = try allocator.alloc([]const u8, 0),
        .path = try allocator.alloc([]const u8, 0),
        .nodes = try allocator.alloc(JsonValue, 0),
        .dpath = try allocator.alloc([]const u8, 0),
        .errs = errs,
    };

    const result = try injectVal(allocator, spec_clone, store_val, inj_init);

    if (errs.items.len > 0) {
        var msg = std.ArrayList(u8).init(allocator);
        try msg.appendSlice("Invalid data: ");
        for (errs.items, 0..) |e, i| {
            if (i > 0) try msg.appendSlice(" | ");
            try msg.appendSlice(e);
        }
        return .{ .out = result, .err = msg.items };
    }
    return .{ .out = result, .err = null };
}

// Validation modify callback — runs after each injection step.
// Matches TS's makeValidation(false) behavior.
fn validationModify(allocator: Allocator, _: JsonValue, key: []const u8, parent: JsonValue, inj: *Injection, _: JsonValue) void {
    // Get the actual data value at this path.
    const cval = getprop(allocator, inj.dparent, JsonValue{ .string = key }, .null) catch .null;
    if (cval == .null and !inj.exact_mode) return;

    const pval = getprop(allocator, parent, JsonValue{ .string = key }, .null) catch .null;
    const ptype = typify(pval);

    // Skip remaining $ command strings.
    if (0 < (@as(i64, T_string) & ptype) and pval == .string) {
        if (std.mem.indexOf(u8, pval.string, S_DS) != null) return;
    }

    const ctype = typify(cval);

    // Type mismatch between spec and data.
    if (ptype != ctype and pval != .null) {
        inj.errs.append(invalidTypeMsg(allocator, inj.path, typename(ptype), cval) catch "type error") catch {};
        return;
    }

    if (ismap(cval)) {
        if (!ismap(pval)) return;

        // Check for unexpected keys (closed-world assumption).
        const pkeys = keysof(allocator, pval) catch return;
        if (pkeys == .array and pkeys.array.data.items.len > 0) {
            // Check for $OPEN flag.
            if (pval == .object) {
                if (pval.object.get(S_BOPEN)) |ov| {
                    if (ov == .bool and ov.bool) {
                        // Open mode: merge data into spec result.
                        const ml = [_]JsonValue{ pval, cval };
                        const ml_lr = allocator.create(ListRef) catch return;
                        ml_lr.* = .{ .data = ListData.init(allocator) };
                        for (ml) |item| ml_lr.append(item) catch {};
                        _ = merge(allocator, JsonValue{ .array = ml_lr }, MAXDEPTH) catch {};
                        if (pval == .object) _ = pval.object.fetchOrderedRemove(S_BOPEN);
                        return;
                    }
                }
            }

            // Closed: report unexpected keys.
            const ckeys = keysof(allocator, cval) catch return;
            if (ckeys == .array) {
                var bad = std.ArrayList([]const u8).init(allocator);
                for (ckeys.array.data.items) |ck| {
                    if (ck != .string) continue;
                    if (!((haskey(allocator, pval, ck) catch false))) {
                        bad.append(ck.string) catch {};
                    }
                }
                if (bad.items.len > 0) {
                    var badmsg = std.ArrayList(u8).init(allocator);
                    badmsg.appendSlice("Unexpected keys at field ") catch {};
                    badmsg.appendSlice(pathifySlice(allocator, if (inj.path.len > 1) inj.path[1..] else inj.path) catch "<root>") catch {};
                    badmsg.appendSlice(": ") catch {};
                    for (bad.items, 0..) |bk, bi| {
                        if (bi > 0) badmsg.appendSlice(", ") catch {};
                        badmsg.appendSlice(bk) catch {};
                    }
                    inj.errs.append(badmsg.items) catch {};
                }
            }
        } else {
            // Empty spec object {} = open, merge in data.
            const ml = [_]JsonValue{ pval, cval };
            const ml_lr = allocator.create(ListRef) catch return;
            ml_lr.* = .{ .data = ListData.init(allocator) };
            for (ml) |item| ml_lr.append(item) catch {};
            _ = merge(allocator, JsonValue{ .array = ml_lr }, MAXDEPTH) catch {};
        }
    } else if (!isnode(cval)) {
        if (inj.exact_mode) {
            // Exact matching for select.
            const a = toStdJson(allocator, cval) catch return;
            const b = toStdJson(allocator, pval) catch return;
            if (!stdJsonEqual(a, b)) {
                const p = pathifySlice(allocator, if (inj.path.len > 1) inj.path[1..] else inj.path) catch "<root>";
                inj.errs.append(std.fmt.allocPrint(allocator, "Value at {s}: {s} should equal {s}.", .{ p, stringify(allocator, cval, null) catch "?", stringify(allocator, pval, null) catch "?" }) catch "exact match error") catch {};
            }
        } else {
            // Non-exact: copy data value into spec result.
            _ = setprop(allocator, parent, JsonValue{ .string = key }, cval) catch {};
        }
    }
}

fn validateWalk(
    allocator: Allocator,
    spec_val: JsonValue,
    data_val: JsonValue,
    errs: *std.ArrayList([]const u8),
    path: []const []const u8,
) anyerror!JsonValue {
    // Type command strings: `$STRING`, `$NUMBER` etc resolve to type checks.
    if (spec_val == .string) {
        const s = spec_val.string;
        if (s.len > 2 and s[0] == '`' and s[s.len - 1] == '`') {
            const cmd = s[1 .. s.len - 1];
            if (std.mem.startsWith(u8, cmd, "$")) {
                return try validateTypeCheck(allocator, cmd, data_val, errs, path);
            }
        }
        // Non-command string: if it matches data, use data value.
        return data_val;
    }

    if (spec_val == .array) {
        // Check for [$ONE, ...] and [$EXACT, ...].
        if (spec_val.array.data.items.len > 0) {
            const first = spec_val.array.data.items[0];
            if (first == .string) {
                if (std.mem.eql(u8, first.string, "`$ONE`")) {
                    return try validateOne(allocator, spec_val, data_val, errs, path);
                }
                if (std.mem.eql(u8, first.string, "`$EXACT`")) {
                    return try validateExact(allocator, spec_val, data_val, errs, path);
                }
                if (std.mem.eql(u8, first.string, "`$CHILD`")) {
                    return try validateChild(allocator, spec_val, data_val, errs, path);
                }
            }
        }
        // Array spec: validate element by element.
        if (data_val != .array) {
            try errs.append(try invalidTypeMsg(allocator, path, S_list, data_val));
            return data_val;
        }
        return data_val;
    }

    if (spec_val == .object) {
        if (data_val != .object) {
            // Check for $CHILD as map key.
            if (spec_val.object.get("`$CHILD`")) |child_spec| {
                return try validateChildMap(allocator, child_spec, data_val, errs, path);
            }
            try errs.append(try invalidTypeMsg(allocator, path, S_map, data_val));
            return data_val;
        }

        // Map validation: check each spec key exists in data.
        const is_open = spec_val.object.get(S_BOPEN) != null;
        var result = try clone(allocator, data_val);

        var it = spec_val.object.iterator();
        while (it.next()) |kv| {
            const k = kv.key_ptr.*;
            if (std.mem.eql(u8, k, S_BOPEN)) continue;
            if (k.len > 0 and k[0] == '`') continue; // Skip command keys.

            var new_path = try allocator.alloc([]const u8, path.len + 1);
            @memcpy(new_path[0..path.len], path);
            new_path[path.len] = k;

            const child_data = if (data_val.object.get(k)) |v| v else .null;
            const child_spec = kv.value_ptr.*;
            const child_result = try validateWalk(allocator, child_spec, child_data, errs, new_path);
            try result.object.put(k, child_result);
        }

        // Check for unexpected keys (closed validation).
        if (!is_open and spec_val.object.count() > 0) {
            var dit = data_val.object.iterator();
            while (dit.next()) |dkv| {
                if (spec_val.object.get(dkv.key_ptr.*) == null) {
                    try errs.append(try std.fmt.allocPrint(
                        allocator,
                        "Unexpected keys at field {s}: {s}",
                        .{ try pathify(allocator, .null, 0, 0), dkv.key_ptr.* },
                    ));
                }
            }
        }

        return result;
    }

    // Scalar spec: treat as default value, use data if available.
    if (data_val != .null) return data_val;
    return spec_val;
}

fn validateTypeCheck(
    allocator: Allocator,
    cmd: []const u8,
    data_val: JsonValue,
    errs: *std.ArrayList([]const u8),
    path: []const []const u8,
) anyerror!JsonValue {
    const t = typify(data_val);

    if (std.mem.eql(u8, cmd, "$STRING")) {
        if (0 == (@as(i64, T_string) & t)) {
            try errs.append(try invalidTypeMsg(allocator, path, S_string, data_val));
            return .null;
        }
        if (data_val == .string and data_val.string.len == 0) {
            const p = try pathifySlice(allocator, path);
            try errs.append(try std.fmt.allocPrint(allocator, "Empty string at {s}", .{p}));
            return .null;
        }
        return data_val;
    }
    if (std.mem.eql(u8, cmd, "$NUMBER")) {
        if (0 == (@as(i64, T_number) & t)) {
            try errs.append(try invalidTypeMsg(allocator, path, S_number, data_val));
            return .null;
        }
        return data_val;
    }
    if (std.mem.eql(u8, cmd, "$INTEGER")) {
        if (0 == (@as(i64, T_integer) & t)) {
            try errs.append(try invalidTypeMsg(allocator, path, S_integer, data_val));
            return .null;
        }
        return data_val;
    }
    if (std.mem.eql(u8, cmd, "$BOOLEAN")) {
        if (0 == (@as(i64, T_boolean) & t)) {
            try errs.append(try invalidTypeMsg(allocator, path, S_boolean, data_val));
            return .null;
        }
        return data_val;
    }
    if (std.mem.eql(u8, cmd, "$OBJECT") or std.mem.eql(u8, cmd, "$MAP")) {
        if (0 == (@as(i64, T_map) & t)) {
            try errs.append(try invalidTypeMsg(allocator, path, S_map, data_val));
            return .null;
        }
        return data_val;
    }
    if (std.mem.eql(u8, cmd, "$ARRAY") or std.mem.eql(u8, cmd, "$LIST")) {
        if (0 == (@as(i64, T_list) & t)) {
            try errs.append(try invalidTypeMsg(allocator, path, S_list, data_val));
            return .null;
        }
        return data_val;
    }
    if (std.mem.eql(u8, cmd, "$ANY")) {
        return data_val;
    }
    if (std.mem.eql(u8, cmd, "$NULL")) {
        if (data_val != .null) {
            try errs.append(try invalidTypeMsg(allocator, path, S_null, data_val));
            return .null;
        }
        return data_val;
    }
    // Unknown command: pass through.
    return data_val;
}

fn validateOne(
    allocator: Allocator,
    spec_val: JsonValue,
    data_val: JsonValue,
    errs: *std.ArrayList([]const u8),
    path: []const []const u8,
) anyerror!JsonValue {
    const alts = spec_val.array.data.items[1..];
    for (alts) |alt| {
        var terrs = std.ArrayList([]const u8).init(allocator);
        _ = try validateWalk(allocator, alt, data_val, &terrs, path);
        if (terrs.items.len == 0) return data_val;
    }
    // No match.
    const p = try pathifySlice(allocator, path);
    try errs.append(try std.fmt.allocPrint(allocator, "Expected one of alternatives at {s}, but found {s}.", .{ p, typename(typify(data_val)) }));
    return data_val;
}

fn validateExact(
    allocator: Allocator,
    spec_val: JsonValue,
    data_val: JsonValue,
    errs: *std.ArrayList([]const u8),
    path: []const []const u8,
) anyerror!JsonValue {
    const alts = spec_val.array.data.items[1..];
    for (alts) |alt| {
        // Deep equality check via conversion to std.json for comparison.
        const a = try toStdJson(allocator, alt);
        const b = try toStdJson(allocator, data_val);
        if (stdJsonEqual(a, b)) return data_val;
        // Also try string comparison.
        const sa = try stringify(allocator, alt, null);
        const sb = try stringify(allocator, data_val, null);
        if (std.mem.eql(u8, sa, sb)) return data_val;
    }
    const p = try pathifySlice(allocator, path);
    try errs.append(try std.fmt.allocPrint(allocator, "Expected exactly equal at {s}, but found {s}.", .{ p, typename(typify(data_val)) }));
    return data_val;
}

fn validateChild(
    allocator: Allocator,
    spec_val: JsonValue,
    data_val: JsonValue,
    errs: *std.ArrayList([]const u8),
    path: []const []const u8,
) anyerror!JsonValue {
    // [$CHILD, template] — validate each element of data array.
    if (spec_val.array.data.items.len < 2) return data_val;
    const tmpl = spec_val.array.data.items[1];

    if (data_val != .array) {
        try errs.append(try invalidTypeMsg(allocator, path, S_list, data_val));
        return data_val;
    }

    for (data_val.array.data.items, 0..) |item, idx| {
        var new_path = try allocator.alloc([]const u8, path.len + 1);
        @memcpy(new_path[0..path.len], path);
        new_path[path.len] = try std.fmt.allocPrint(allocator, "{d}", .{idx});
        _ = try validateWalk(allocator, tmpl, item, errs, new_path);
    }
    return data_val;
}

fn validateChildMap(
    allocator: Allocator,
    child_spec: JsonValue,
    data_val: JsonValue,
    errs: *std.ArrayList([]const u8),
    path: []const []const u8,
) anyerror!JsonValue {
    if (data_val != .object) {
        try errs.append(try invalidTypeMsg(allocator, path, S_map, data_val));
        return data_val;
    }
    var it = data_val.object.iterator();
    while (it.next()) |kv| {
        var new_path = try allocator.alloc([]const u8, path.len + 1);
        @memcpy(new_path[0..path.len], path);
        new_path[path.len] = kv.key_ptr.*;
        _ = try validateWalk(allocator, child_spec, kv.value_ptr.*, errs, new_path);
    }
    return data_val;
}

fn invalidTypeMsg(allocator: Allocator, path: []const []const u8, expected: []const u8, val: JsonValue) anyerror![]const u8 {
    const p = try pathifySlice(allocator, path);
    const actual = typename(typify(val));
    const val_str = try stringify(allocator, val, 33);
    if (path.len == 0) {
        if (val == .null) {
            return try std.fmt.allocPrint(allocator, "Expected {s}, but found no value.", .{expected});
        }
        return try std.fmt.allocPrint(allocator, "Expected {s}, but found {s}: {s}.", .{ expected, actual, val_str });
    }
    return try std.fmt.allocPrint(allocator, "Expected {s}, field {s} to be {s}, but found {s}: {s}.", .{ expected, p, expected, actual, val_str });
}

fn pathifySlice(allocator: Allocator, path: []const []const u8) anyerror![]const u8 {
    if (path.len == 0) return "<root>";
    var buf = std.ArrayList(u8).init(allocator);
    for (path, 0..) |p, i| {
        if (i > 0) try buf.append('.');
        try buf.appendSlice(p);
    }
    return buf.items;
}

fn stdJsonEqual(a: StdJsonValue, b: StdJsonValue) bool {
    // Use the runner's equality check logic.
    const TagType = std.meta.Tag(StdJsonValue);
    const tag_a: TagType = a;
    const tag_b: TagType = b;

    if ((tag_a == .integer or tag_a == .float) and (tag_b == .integer or tag_b == .float)) {
        const fa: f64 = if (tag_a == .integer) @floatFromInt(a.integer) else a.float;
        const fb: f64 = if (tag_b == .integer) @floatFromInt(b.integer) else b.float;
        return fa == fb;
    }
    if (tag_a != tag_b) return false;
    return switch (a) {
        .null => true,
        .bool => |av| av == b.bool,
        .integer => |av| av == b.integer,
        .float => |av| av == b.float,
        .string => |av| std.mem.eql(u8, av, b.string),
        .number_string => |av| std.mem.eql(u8, av, b.number_string),
        .array => |av| {
            const bv = b.array;
            if (av.items.len != bv.items.len) return false;
            for (av.items, bv.items) |ai, bi| {
                if (!stdJsonEqual(ai, bi)) return false;
            }
            return true;
        },
        .object => |av| {
            const bv = b.object;
            if (av.count() != bv.count()) return false;
            var it = av.iterator();
            while (it.next()) |kv| {
                const bval = bv.get(kv.key_ptr.*) orelse return false;
                if (!stdJsonEqual(kv.value_ptr.*, bval)) return false;
            }
            return true;
        },
    };
}

// ============================================================================
// Select — filter children matching a query.
// ============================================================================

pub fn selectFn(allocator: Allocator, children: JsonValue, query: JsonValue) anyerror!JsonValue {
    if (!isnode(children)) return try JsonValue.makeList(allocator);

    // Normalize children: add $KEY for map/list items.
    var child_list = std.ArrayList(JsonValue).init(allocator);

    if (ismap(children)) {
        const pairs = try items(allocator, children);
        if (pairs == .array) {
            for (pairs.array.data.items) |pair| {
                if (pair != .array or pair.array.data.items.len < 2) continue;
                const k = pair.array.data.items[0];
                var child = pair.array.data.items[1];
                if (ismap(child)) {
                    try child.object.put("$KEY", k);
                }
                try child_list.append(child);
            }
        }
    } else if (islist(children)) {
        for (children.array.data.items, 0..) |child_raw, idx| {
            var child = child_raw;
            if (ismap(child)) {
                try child.object.put("$KEY", JsonValue{ .integer = @intCast(idx) });
            }
            try child_list.append(child);
        }
    }

    // For each child, try validating with exact matching against the query.
    const result_lr = try allocator.create(ListRef);
    result_lr.* = .{ .data = ListData.init(allocator) };

    for (child_list.items) |child| {
        var terrs = std.ArrayList([]const u8).init(allocator);
        const q = try clone(allocator, query);

        // Mark all maps in query as open.
        _ = try walk(allocator, q, markOpen, null, MAXDEPTH);

        // Validate with exact matching.
        _ = try validateExactMatch(allocator, q, child, &terrs, &[_][]const u8{});

        if (terrs.items.len == 0) {
            try result_lr.append(child);
        }
    }

    return JsonValue{ .array = result_lr };
}

fn markOpen(_: Allocator, _: ?[]const u8, val: JsonValue, _: JsonValue, _: []const []const u8) anyerror!JsonValue {
    if (val == .object) {
        val.object.put(S_BOPEN, JsonValue{ .bool = true }) catch {};
    }
    return val;
}

fn validateExactMatch(
    allocator: Allocator,
    spec_val: JsonValue,
    data_val: JsonValue,
    errs: *std.ArrayList([]const u8),
    path: []const []const u8,
) anyerror!JsonValue {
    // Operator handling for select queries.
    if (spec_val == .object) {
        // Check for operators.
        if (spec_val.object.get("`$AND`")) |terms| {
            return try selectAnd(allocator, terms, data_val, errs, path);
        }
        if (spec_val.object.get("`$OR`")) |terms| {
            return try selectOr(allocator, terms, data_val, errs, path);
        }
        if (spec_val.object.get("`$NOT`")) |term| {
            return try selectNot(allocator, term, data_val, errs, path);
        }
        if (spec_val.object.get("`$GT`")) |term| {
            return try selectCmp(allocator, "$GT", term, data_val, errs, path);
        }
        if (spec_val.object.get("`$LT`")) |term| {
            return try selectCmp(allocator, "$LT", term, data_val, errs, path);
        }
        if (spec_val.object.get("`$GTE`")) |term| {
            return try selectCmp(allocator, "$GTE", term, data_val, errs, path);
        }
        if (spec_val.object.get("`$LTE`")) |term| {
            return try selectCmp(allocator, "$LTE", term, data_val, errs, path);
        }
        if (spec_val.object.get("`$LIKE`")) |term| {
            return try selectCmp(allocator, "$LIKE", term, data_val, errs, path);
        }

        if (data_val != .object) {
            try errs.append("type mismatch: expected object");
            return data_val;
        }

        // Match each spec key against data (open: extra data keys are OK).
        var it = spec_val.object.iterator();
        while (it.next()) |kv| {
            const k = kv.key_ptr.*;
            if (std.mem.eql(u8, k, S_BOPEN)) continue;
            if (k.len > 0 and k[0] == '`') continue;

            var new_path = try allocator.alloc([]const u8, path.len + 1);
            @memcpy(new_path[0..path.len], path);
            new_path[path.len] = k;

            const child_data = if (data_val.object.get(k)) |v| v else .null;
            _ = try validateExactMatch(allocator, kv.value_ptr.*, child_data, errs, new_path);
        }
        return data_val;
    }

    if (spec_val == .array) {
        if (spec_val.array.data.items.len > 0) {
            const first = spec_val.array.data.items[0];
            if (first == .string) {
                if (std.mem.eql(u8, first.string, "`$ONE`"))
                    return try validateOne(allocator, spec_val, data_val, errs, path);
                if (std.mem.eql(u8, first.string, "`$EXACT`"))
                    return try validateExact(allocator, spec_val, data_val, errs, path);
            }
        }
        return data_val;
    }

    if (spec_val == .string) {
        const s = spec_val.string;
        if (s.len > 2 and s[0] == '`' and s[s.len - 1] == '`') {
            const cmd = s[1 .. s.len - 1];
            if (std.mem.startsWith(u8, cmd, "$")) {
                return try validateTypeCheck(allocator, cmd, data_val, errs, path);
            }
        }
    }

    // Exact scalar match.
    const a = try toStdJson(allocator, spec_val);
    const b = try toStdJson(allocator, data_val);
    if (!stdJsonEqual(a, b)) {
        const p = try pathifySlice(allocator, path);
        try errs.append(try std.fmt.allocPrint(
            allocator,
            "Value at {s}: {s} should equal {s}.",
            .{ p, try stringify(allocator, data_val, null), try stringify(allocator, spec_val, null) },
        ));
    }
    return data_val;
}

fn selectAnd(
    allocator: Allocator,
    terms: JsonValue,
    data_val: JsonValue,
    errs: *std.ArrayList([]const u8),
    path: []const []const u8,
) anyerror!JsonValue {
    if (terms != .array) return data_val;
    for (terms.array.data.items) |term| {
        var terrs = std.ArrayList([]const u8).init(allocator);
        _ = try validateExactMatch(allocator, term, data_val, &terrs, path);
        if (terrs.items.len > 0) {
            try errs.append("AND condition failed");
            return data_val;
        }
    }
    return data_val;
}

fn selectOr(
    allocator: Allocator,
    terms: JsonValue,
    data_val: JsonValue,
    errs: *std.ArrayList([]const u8),
    path: []const []const u8,
) anyerror!JsonValue {
    if (terms != .array) return data_val;
    for (terms.array.data.items) |term| {
        var terrs = std.ArrayList([]const u8).init(allocator);
        _ = try validateExactMatch(allocator, term, data_val, &terrs, path);
        if (terrs.items.len == 0) return data_val;
    }
    try errs.append("OR: no condition matched");
    return data_val;
}

fn selectNot(
    allocator: Allocator,
    term: JsonValue,
    data_val: JsonValue,
    errs: *std.ArrayList([]const u8),
    path: []const []const u8,
) anyerror!JsonValue {
    var terrs = std.ArrayList([]const u8).init(allocator);
    _ = try validateExactMatch(allocator, term, data_val, &terrs, path);
    if (terrs.items.len == 0) {
        try errs.append("NOT: condition should not have matched");
    }
    return data_val;
}

fn selectCmp(
    allocator: Allocator,
    op: []const u8,
    term: JsonValue,
    data_val: JsonValue,
    errs: *std.ArrayList([]const u8),
    path: []const []const u8,
) anyerror!JsonValue {
    _ = path;
    const pf = toFloat(data_val);
    const tf = toFloat(term);

    var pass = false;
    if (std.mem.eql(u8, op, "$GT")) {
        if (pf != null and tf != null) pass = pf.? > tf.?;
    } else if (std.mem.eql(u8, op, "$LT")) {
        if (pf != null and tf != null) pass = pf.? < tf.?;
    } else if (std.mem.eql(u8, op, "$GTE")) {
        if (pf != null and tf != null) pass = pf.? >= tf.?;
    } else if (std.mem.eql(u8, op, "$LTE")) {
        if (pf != null and tf != null) pass = pf.? <= tf.?;
    } else if (std.mem.eql(u8, op, "$LIKE")) {
        if (term == .string) {
            const subject = try stringify(allocator, data_val, null);
            pass = regexMatch(term.string, subject);
        }
    }

    if (!pass) {
        try errs.append(try std.fmt.allocPrint(allocator, "CMP {s} failed", .{op}));
    }
    return data_val;
}

fn toFloat(val: JsonValue) ?f64 {
    return switch (val) {
        .integer => |i| @floatFromInt(i),
        .float => |f| f,
        else => null,
    };
}

// Regex matching via mvzr (pure Zig, cross-platform).
const mvzr = @import("mvzr");

fn regexMatch(pattern: []const u8, subject: []const u8) bool {
    const regex = mvzr.compile(pattern) orelse return false;
    return regex.isMatch(subject);
}
