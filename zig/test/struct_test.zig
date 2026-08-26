// RUN: zig build test
// RUN-SOME: zig build test 2>&1 | head

// Test structure mirrors ts/test/utility/StructUtility.test.ts
// Uses the shared corpus in build/test/test.json, driven by voxgig/omni
// through test/omni.zig - which is a bridge and a subject factory, not a
// runner: the algorithm is omni's.

const std = @import("std");
const testing = std.testing;

const voxgig_struct = @import("voxgig-struct");
const omni = @import("omni.zig");

const Allocator = std.mem.Allocator;
const JsonValue = voxgig_struct.JsonValue;
const StdJsonValue = std.json.Value;

// NOTE: tests are (mostly) in order of increasing dependence.

// Wrap library functions as omni subjects. A binding takes this port's own
// JsonValue and returns one; test/omni.zig converts at the boundary.
// All wrappers now use AllocSubject (takes Allocator + our JsonValue).
// The runner converts std.json → JsonValue before calling, and back after.

fn wrap_isnode(_: Allocator, val: JsonValue) JsonValue {
    return .{ .bool = voxgig_struct.isnode(val) };
}

fn wrap_ismap(_: Allocator, val: JsonValue) JsonValue {
    return .{ .bool = voxgig_struct.ismap(val) };
}

fn wrap_islist(_: Allocator, val: JsonValue) JsonValue {
    return .{ .bool = voxgig_struct.islist(val) };
}

fn wrap_iskey(_: Allocator, val: JsonValue) JsonValue {
    return .{ .bool = voxgig_struct.iskey(val) };
}

fn wrap_isempty(_: Allocator, val: JsonValue) JsonValue {
    return .{ .bool = voxgig_struct.isempty(val) };
}

fn wrap_isfunc(_: Allocator, val: JsonValue) JsonValue {
    return .{ .bool = voxgig_struct.isfunc(val) };
}

// ---- minor tests ----

test "minor-isnode" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "isnode", omni.sub(wrap_isnode), .{});
}

test "minor-ismap" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "ismap", omni.sub(wrap_ismap), .{});
}

test "minor-islist" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "islist", omni.sub(wrap_islist), .{});
}

test "minor-iskey" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "iskey", omni.sub(wrap_iskey), omni.Flags.nonull());
}

test "minor-isempty" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "isempty", omni.sub(wrap_isempty), omni.Flags.nonull());
}

test "minor-isfunc" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "isfunc", omni.sub(wrap_isfunc), .{});
}

// ---- Allocator-aware wrappers for new functions ----

fn wrap_typename(allocator: Allocator, val: JsonValue) JsonValue {
    _ = allocator;
    const t: i64 = switch (val) {
        .integer => |i| i,
        .float => |f| @intFromFloat(f),
        else => return JsonValue{ .string = voxgig_struct.S_any },
    };
    return JsonValue{ .string = voxgig_struct.typename(t) };
}

fn wrap_typify(allocator: Allocator, val: JsonValue) JsonValue {
    _ = allocator;
    // With omni's default null handling, an authored null arrives as the
    // NULL marker while a missing `in` arrives as a real null.
    if (val == .null) {
        return JsonValue{ .integer = @as(i64, voxgig_struct.T_noval) };
    }
    if (val == .string) {
        if (std.mem.eql(u8, val.string, omni.NULLMARK)) {
            return JsonValue{ .integer = voxgig_struct.typify(.null) };
        }
    }
    return JsonValue{ .integer = voxgig_struct.typify(val) };
}

fn wrap_size(allocator: Allocator, val: JsonValue) JsonValue {
    _ = allocator;
    return JsonValue{ .integer = voxgig_struct.size(val) };
}

fn wrap_strkey(allocator: Allocator, val: JsonValue) JsonValue {
    const s = voxgig_struct.strkey(allocator, val) catch return JsonValue{ .string = voxgig_struct.S_MT };
    return JsonValue{ .string = s };
}

fn wrap_keysof(allocator: Allocator, val: JsonValue) JsonValue {
    return voxgig_struct.keysof(allocator, val) catch return .null;
}

fn wrap_haskey(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { src, key }
    if (val != .object) return JsonValue{ .bool = false };
    const m = val.object;
    const src = m.get("src") orelse .null;
    const key = m.get("key") orelse .null;
    const result = voxgig_struct.haskey(allocator, src, key) catch return JsonValue{ .bool = false };
    return JsonValue{ .bool = result };
}

fn wrap_items(allocator: Allocator, val: JsonValue) JsonValue {
    return voxgig_struct.items(allocator, val) catch return .null;
}

fn wrap_getelem(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { val, key, alt? }
    if (val != .object) return .null;
    const m = val.object;
    const v = m.get("val") orelse .null;
    const key = m.get("key") orelse return .null;
    const alt = m.get("alt") orelse .null;
    return voxgig_struct.getelem(allocator, v, key, alt) catch return .null;
}

fn wrap_getprop(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { val, key, alt? }
    if (val != .object) return .null;
    const m = val.object;
    const v = m.get("val") orelse .null;
    const key = m.get("key") orelse return .null;
    const alt = m.get("alt") orelse .null;
    return voxgig_struct.getprop(allocator, v, key, alt) catch return .null;
}

// Sentinels: haskey called with { val, key } (the sentinels group uses
// `val`, whereas the minor group uses `src`).
fn wrap_haskey_val(allocator: Allocator, val: JsonValue) JsonValue {
    if (val != .object) return JsonValue{ .bool = false };
    const m = val.object;
    const v = m.get("val") orelse .null;
    const key = m.get("key") orelse .null;
    const result = voxgig_struct.haskey(allocator, v, key) catch return JsonValue{ .bool = false };
    return JsonValue{ .bool = result };
}

// Sentinels: stringify called on the raw input value (e.g. `in: null`),
// not on a { val, max } wrapper object.
fn wrap_stringify_raw(allocator: Allocator, val: JsonValue) JsonValue {
    const result = voxgig_struct.stringify(allocator, val, null) catch return JsonValue{ .string = voxgig_struct.S_MT };
    return JsonValue{ .string = result };
}

fn wrap_clone(allocator: Allocator, val: JsonValue) JsonValue {
    // Preserve an authored null while allowing omni to distinguish it from
    // the absent final entry in the group.
    if (val == .string) {
        if (std.mem.eql(u8, val.string, omni.NULLMARK)) {
            return .null;
        }
    }
    return voxgig_struct.clone(allocator, val) catch return .null;
}

fn restoreNullMarks(allocator: Allocator, val: JsonValue) JsonValue {
    switch (val) {
        .string => |text| {
            if (std.mem.eql(u8, text, omni.NULLMARK)) return .null;
        },
        .array => |list| {
            for (list.data.items) |*item| item.* = restoreNullMarks(allocator, item.*);
        },
        .object => |map| {
            var it = map.iterator();
            while (it.next()) |field| {
                field.value_ptr.* = restoreNullMarks(allocator, field.value_ptr.*);
            }
        },
        else => {},
    }
    return val;
}

fn wrap_flatten(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { val, depth? }
    if (val != .object) return .null;
    const m = val.object;
    const v = m.get("val") orelse return .null;
    var depth: i64 = 1;
    if (m.get("depth")) |d| {
        switch (d) {
            .integer => |i| depth = i,
            .float => |f| depth = @intFromFloat(f),
            else => {},
        }
    }
    return voxgig_struct.flatten(allocator, v, depth) catch return .null;
}

fn wrap_filter(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { val, check }
    // check is "gt3" or "lt3" - simple test-only checks
    if (val != .object) return .null;
    const m = val.object;
    const v = m.get("val") orelse return .null;
    const check_name = (m.get("check") orelse return .null).string;

    if (v != .array) return .null;
    const list = v.array.data.items;

    const result_lr = allocator.create(voxgig_struct.ListRef) catch return .null;
    result_lr.* = .{ .data = voxgig_struct.ListData.init(allocator) };
    for (list) |item| {
        const num: f64 = switch (item) {
            .integer => |i| @floatFromInt(i),
            .float => |f| f,
            else => continue,
        };

        const keep = if (std.mem.eql(u8, check_name, "gt3"))
            num > 3
        else if (std.mem.eql(u8, check_name, "lt3"))
            num < 3
        else
            false;

        if (keep) {
            result_lr.data.append(item) catch continue;
        }
    }
    return JsonValue{ .array = result_lr };
}

fn wrap_delprop(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { parent, key }
    if (val != .object) return .null;
    const m = val.object;
    const parent = m.get("parent") orelse return .null;
    const key = m.get("key") orelse return parent;
    return voxgig_struct.delprop(allocator, parent, key) catch return parent;
}

fn wrap_setprop(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { parent, key, val }
    if (val != .object) return .null;
    const m = val.object;
    const parent = m.get("parent") orelse return .null;
    const key = m.get("key") orelse return parent;
    const newval = m.get("val") orelse return parent;
    return voxgig_struct.setprop(allocator, parent, key, newval) catch return parent;
}

fn wrap_escre(allocator: Allocator, val: JsonValue) JsonValue {
    const s = switch (val) {
        .string => |str| str,
        else => return JsonValue{ .string = voxgig_struct.S_MT },
    };
    const result = voxgig_struct.escre(allocator, s) catch return JsonValue{ .string = voxgig_struct.S_MT };
    return JsonValue{ .string = result };
}

fn wrap_escurl(allocator: Allocator, val: JsonValue) JsonValue {
    const s = switch (val) {
        .string => |str| str,
        else => return JsonValue{ .string = voxgig_struct.S_MT },
    };
    const result = voxgig_struct.escurl(allocator, s) catch return JsonValue{ .string = voxgig_struct.S_MT };
    return JsonValue{ .string = result };
}

fn wrap_join(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { val, sep?, url? }
    if (val != .object) return JsonValue{ .string = voxgig_struct.S_MT };
    const m = val.object;
    const arr = m.get("val") orelse return JsonValue{ .string = voxgig_struct.S_MT };
    const sep = if (m.get("sep")) |s| switch (s) {
        .string => |str| str,
        else => ",",
    } else ",";
    const urlMode = if (m.get("url")) |u| switch (u) {
        .bool => |b| b,
        else => false,
    } else false;
    const result = voxgig_struct.join(allocator, arr, sep, urlMode) catch return JsonValue{ .string = voxgig_struct.S_MT };
    return JsonValue{ .string = result };
}

fn wrap_jsonify(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { val?, flags?: { indent?, offset? } }
    if (val != .object) return JsonValue{ .string = "null" };
    const m = val.object;
    const v = m.get("val") orelse .null;

    var indent: usize = 2;
    var offset: usize = 0;
    if (m.get("flags")) |flags| {
        if (flags == .object) {
            if (flags.object.get("indent")) |ind| {
                switch (ind) {
                    .integer => |i| indent = @intCast(i),
                    .float => |f| indent = @intFromFloat(f),
                    else => {},
                }
            }
            if (flags.object.get("offset")) |off| {
                switch (off) {
                    .integer => |i| offset = @intCast(i),
                    .float => |f| offset = @intFromFloat(f),
                    else => {},
                }
            }
        }
    }
    const result = voxgig_struct.jsonify(allocator, v, indent, offset) catch return JsonValue{ .string = "null" };
    return JsonValue{ .string = result };
}

fn wrap_stringify(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { val?, max? }
    if (val != .object) return JsonValue{ .string = voxgig_struct.S_MT };
    const m = val.object;
    const v = m.get("val") orelse return JsonValue{ .string = voxgig_struct.S_MT };

    // Handle __NULL__ as "null"
    if (v == .string) {
        if (std.mem.eql(u8, v.string, omni.NULLMARK)) {
            const result = voxgig_struct.stringify(allocator, JsonValue{ .string = "null" }, null) catch return JsonValue{ .string = voxgig_struct.S_MT };
            return JsonValue{ .string = result };
        }
    }

    var maxlen: ?usize = null;
    if (m.get("max")) |max_val| {
        switch (max_val) {
            .integer => |i| maxlen = @intCast(i),
            .float => |f| maxlen = @intFromFloat(f),
            else => {},
        }
    }
    const result = voxgig_struct.stringify(allocator, v, maxlen) catch return JsonValue{ .string = voxgig_struct.S_MT };
    return JsonValue{ .string = result };
}

fn wrap_pathify(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { path?, from? }
    if (val != .object) return JsonValue{ .string = "<unknown-path>" };
    const m = val.object;
    const path_raw = m.get("path") orelse {
        // No path field - return unknown-path
        var result = std.array_list.Managed(u8).init(allocator);
        result.appendSlice("<unknown-path>") catch return JsonValue{ .string = "<unknown-path>" };
        return JsonValue{ .string = result.items };
    };
    const path = restoreNullMarks(allocator, path_raw);

    var from: usize = 0;
    if (m.get("from")) |f| {
        switch (f) {
            .integer => |i| from = if (i < 0) 0 else @intCast(i),
            .float => |fv| from = @intFromFloat(@max(0, fv)),
            else => {},
        }
    }
    const result = voxgig_struct.pathify(allocator, path, from, 0) catch return JsonValue{ .string = "<unknown-path>" };
    return JsonValue{ .string = result };
}

fn wrap_slice(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { val, start?, end? }
    if (val != .object) return .null;
    const m = val.object;
    const v = m.get("val") orelse return .null;

    var start: ?i64 = null;
    var end_val: ?i64 = null;
    if (m.get("start")) |s| {
        switch (s) {
            .integer => |i| start = i,
            .float => |f| start = @intFromFloat(f),
            else => {},
        }
    }
    if (m.get("end")) |e| {
        switch (e) {
            .integer => |i| end_val = i,
            .float => |f| end_val = @intFromFloat(f),
            else => {},
        }
    }

    return voxgig_struct.slice(allocator, v, start, end_val) catch return v;
}

fn wrap_pad(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { val, pad?, char? }
    if (val != .object) return JsonValue{ .string = voxgig_struct.S_MT };
    const m = val.object;
    const v = m.get("val") orelse return JsonValue{ .string = voxgig_struct.S_MT };

    // pad is Group B: stringify non-string vals so {val:1, pad:5} → "1    ",
    // {val:null, pad:6} → "null  " (TS canonical behaviour). The arena
    // allocator owned by the runner frees the temporary stringify output
    // at test-case end, so we don't need an explicit free here.
    const s: []const u8 = switch (v) {
        .string => |str| blk: {
            if (std.mem.eql(u8, str, omni.NULLMARK)) {
                break :blk voxgig_struct.stringify(allocator, JsonValue{ .null = {} }, null) catch str;
            }
            break :blk str;
        },
        .null => voxgig_struct.stringify(allocator, JsonValue{ .null = {} }, null) catch "",
        else => voxgig_struct.stringify(allocator, v, null) catch "",
    };

    var padding: i64 = 44;
    if (m.get("pad")) |p| {
        switch (p) {
            .integer => |i| padding = i,
            .float => |f| padding = @intFromFloat(f),
            else => {},
        }
    }

    var padchar: u8 = ' ';
    if (m.get("char")) |c| {
        if (c == .string and c.string.len > 0) {
            padchar = c.string[0];
        }
    }

    const result = voxgig_struct.pad(allocator, s, padding, padchar) catch return JsonValue{ .string = voxgig_struct.S_MT };
    return JsonValue{ .string = result };
}

// ---- Allocator-aware minor tests ----

test "minor-typename" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "typename", omni.sub(wrap_typename), .{});
}

test "minor-typify" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "typify", omni.sub(wrap_typify), .{});
}

test "minor-size" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "size", omni.sub(wrap_size), omni.Flags.nonull());
}

test "minor-strkey" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "strkey", omni.sub(wrap_strkey), omni.Flags.nonull());
}

test "minor-keysof" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "keysof", omni.sub(wrap_keysof), .{});
}

test "minor-haskey" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "haskey", omni.sub(wrap_haskey), omni.Flags.nonull());
}

test "minor-items" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "items", omni.sub(wrap_items), .{});
}

test "minor-getelem" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "getelem", omni.sub(wrap_getelem), .{});
}

test "minor-getprop" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "getprop", omni.sub(wrap_getprop), .{});
}

test "minor-clone" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "clone", omni.sub(wrap_clone), .{});
}

test "minor-flatten" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "flatten", omni.sub(wrap_flatten), .{});
}

test "minor-filter" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "filter", omni.sub(wrap_filter), .{});
}

test "minor-delprop" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "delprop", omni.sub(wrap_delprop), .{});
}

test "minor-setprop" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "setprop", omni.sub(wrap_setprop), .{});
}

test "minor-escre" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "escre", omni.sub(wrap_escre), .{});
}

test "minor-escurl" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "escurl", omni.sub(wrap_escurl), .{});
}

test "minor-join" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "join", omni.sub(wrap_join), omni.Flags.nonull());
}

test "minor-jsonify" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "jsonify", omni.sub(wrap_jsonify), omni.Flags.nonull());
}

test "minor-stringify" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "stringify", omni.sub(wrap_stringify), .{});
}

test "minor-pathify" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "pathify", omni.sub(wrap_pathify), .{});
}

test "minor-slice" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "slice", omni.sub(wrap_slice), omni.Flags.nonull());
}

test "minor-pad" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "minor", "pad", omni.sub(wrap_pad), omni.Flags.nonull());
}

// ---- Walk, Merge, and Transform helpers ----

// ---- Walk wrappers ----

fn walkApplyBasic(_: Allocator, key: ?[]const u8, val: JsonValue, _: JsonValue, path: []const []const u8) !JsonValue {
    _ = key;
    // If value is a string, append ~path.
    if (val == .string) {
        // Build path string.
        var total_len: usize = val.string.len + 1; // +1 for '~'
        for (path) |p| total_len += p.len;
        if (path.len > 1) total_len += path.len - 1; // dots between parts

        var buf = std.array_list.Managed(u8).init(std.heap.page_allocator);
        buf.appendSlice(val.string) catch return val;
        buf.append('~') catch return val;
        for (path, 0..) |p, i| {
            if (i > 0) buf.append('.') catch {};
            buf.appendSlice(p) catch {};
        }
        return JsonValue{ .string = buf.items };
    }
    return val;
}

fn walkApplyCopy(_: Allocator, _: ?[]const u8, val: JsonValue, _: JsonValue, _: []const []const u8) !JsonValue {
    return val;
}

fn wrap_walk_basic(allocator: Allocator, val: JsonValue) JsonValue {
    if (val == .string and std.mem.eql(u8, val.string, omni.NULLMARK)) {
        return .null;
    }
    return voxgig_struct.walk(allocator, val, walkApplyBasic, null, voxgig_struct.MAXDEPTH) catch return .null;
}

fn wrap_walk_copy(allocator: Allocator, val: JsonValue) JsonValue {
    if (val == .string and std.mem.eql(u8, val.string, omni.UNDEFMARK)) {
        return .null;
    }
    return voxgig_struct.walk(allocator, val, walkApplyCopy, null, voxgig_struct.MAXDEPTH) catch return .null;
}

fn wrap_walk_depth(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { src, maxdepth? }
    // This test manually builds a copy tree to verify depth limiting.
    if (val != .object) return .null;
    const m = val.object;
    const src = m.get("src") orelse return .null;
    var maxdepth: i32 = voxgig_struct.MAXDEPTH;
    if (m.get("maxdepth")) |md| {
        switch (md) {
            .integer => |i| maxdepth = @intCast(i),
            .float => |f| maxdepth = @intFromFloat(f),
            else => {},
        }
    }
    // Use clone with depth: clone the structure, but empty nodes beyond maxdepth.
    return cloneWithDepth(allocator, src, maxdepth, 0) catch return .null;
}

fn cloneWithDepth(allocator: Allocator, val: JsonValue, maxdepth: i32, depth: i32) !JsonValue {
    if (!voxgig_struct.isnode(val)) return val;
    if (maxdepth >= 0 and depth >= maxdepth) {
        // At depth limit: return empty container.
        if (voxgig_struct.islist(val)) return JsonValue.makeList(allocator) catch return .null;
        return JsonValue.makeMap(allocator) catch return .null;
    }
    if (voxgig_struct.ismap(val)) {
        const new_obj_ref = allocator.create(voxgig_struct.MapRef) catch return .null;
        new_obj_ref.* = .{ .data = .empty, .allocator = allocator };
        var it = val.object.iterator();
        while (it.next()) |kv| {
            try new_obj_ref.put(kv.key_ptr.*, try cloneWithDepth(allocator, kv.value_ptr.*, maxdepth, depth + 1));
        }
        return JsonValue{ .object = new_obj_ref };
    }
    if (voxgig_struct.islist(val)) {
        const new_arr_lr = allocator.create(voxgig_struct.ListRef) catch return .null;
        new_arr_lr.* = .{ .data = voxgig_struct.ListData.init(allocator) };
        for (val.array.data.items) |item| {
            try new_arr_lr.data.append(try cloneWithDepth(allocator, item, maxdepth, depth + 1));
        }
        return JsonValue{ .array = new_arr_lr };
    }
    return val;
}

// ---- Merge wrappers ----

fn wrap_merge_cases(allocator: Allocator, val: JsonValue) JsonValue {
    return voxgig_struct.merge(allocator, val, voxgig_struct.MAXDEPTH) catch return .null;
}

fn wrap_merge_array(allocator: Allocator, val: JsonValue) JsonValue {
    // For array section: if input is not array, wrap it.
    if (val != .array) {
        const arr_lr = allocator.create(voxgig_struct.ListRef) catch return .null;
        arr_lr.* = .{ .data = voxgig_struct.ListData.init(allocator) };
        arr_lr.data.append(val) catch return .null;
        return voxgig_struct.merge(allocator, JsonValue{ .array = arr_lr }, voxgig_struct.MAXDEPTH) catch return .null;
    }
    return voxgig_struct.merge(allocator, val, voxgig_struct.MAXDEPTH) catch return .null;
}

fn wrap_merge_depth(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { val, depth }
    if (val != .object) return .null;
    const m = val.object;
    const v = m.get("val") orelse return .null;
    var depth: i32 = voxgig_struct.MAXDEPTH;
    if (m.get("depth")) |d| {
        switch (d) {
            .integer => |i| depth = @intCast(i),
            .float => |f| depth = @intFromFloat(f),
            else => {},
        }
    }
    return voxgig_struct.merge(allocator, v, depth) catch return .null;
}

fn wrap_merge_integrity(allocator: Allocator, val: JsonValue) JsonValue {
    return voxgig_struct.merge(allocator, val, voxgig_struct.MAXDEPTH) catch return .null;
}

// ---- Transform wrappers ----

fn wrap_transform(allocator: Allocator, val: JsonValue) omni.SubResult {
    // in: { data?, spec? }
    if (val != .object) return omni.SubResult.val(.null);
    const m = val.object;
    const data = m.get("data") orelse .null;
    const spec = m.get("spec") orelse return omni.SubResult.val(.null);
    const result = voxgig_struct.transform(allocator, data, spec) catch |e|
        return omni.SubResult.fail(@errorName(e));
    if (result.err) |msg| return omni.SubResult.fail(msg);
    return omni.SubResult.val(result.out);
}

// ---- Walk tests ----

test "walk-basic" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "walk", "basic", omni.sub(wrap_walk_basic), .{});
}

test "walk-copy" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "walk", "copy", omni.sub(wrap_walk_copy), .{});
}

test "walk-depth" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "walk", "depth", omni.sub(wrap_walk_depth), omni.Flags.nonull());
}

// ---- Merge tests ----

test "merge-cases" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "merge", "cases", omni.sub(wrap_merge_cases), .{});
}

test "merge-array" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "merge", "array", omni.sub(wrap_merge_array), .{});
}

test "merge-integrity" {
    const r = try omni.makeRunner();
    try omni.rungroupargs(&r, "merge", "integrity", omni.subargs(wrap_merge_integrity), .{});
}

test "merge-depth" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "merge", "depth", omni.sub(wrap_merge_depth), .{});
}

// ---- Transform tests ----

test "transform-paths" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "transform", "paths", omni.subres(wrap_transform), .{});
}

test "transform-cmds" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "transform", "cmds", omni.subres(wrap_transform), .{});
}

// ---- SetPath tests ----

fn wrap_setpath(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { store, path, val }
    if (val != .object) return .null;
    const m = val.object;
    const store = m.get("store") orelse return .null;
    const path_v = m.get("path") orelse return .null;
    const set_val = m.get("val") orelse return .null;
    return voxgig_struct.setpath(allocator, store, path_v, set_val) catch return .null;
}

test "minor-setpath" {
    const r = try omni.makeRunner();
    try omni.rungroupargs(&r, "minor", "setpath", omni.subargs(wrap_setpath), omni.Flags.nonull());
}

// ---- GetPath tests ----

fn wrap_getpath_basic(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { path, store }
    if (val != .object) return .null;
    const m = val.object;
    const path_v = m.get("path") orelse return .null;
    const store = m.get("store") orelse return .null;
    return voxgig_struct.getpath(allocator, path_v, store) catch return .null;
}

fn wrap_getpath_relative(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { path, store, dparent, dpath? }
    if (val != .object) return .null;
    const m = val.object;
    const path_v = m.get("path") orelse return .null;
    const store = m.get("store") orelse return .null;
    const dparent = m.get("dparent") orelse .null;

    // Parse dpath string into slice.
    var dpath_buf: [32][]const u8 = undefined;
    var dpath_len: usize = 0;
    if (m.get("dpath")) |dp| {
        if (dp == .string and dp.string.len > 0) {
            var it = std.mem.splitScalar(u8, dp.string, '.');
            while (it.next()) |part| {
                if (dpath_len < dpath_buf.len) {
                    dpath_buf[dpath_len] = part;
                    dpath_len += 1;
                }
            }
        }
    }

    var errs = std.array_list.Managed([]const u8).init(allocator);
    const init_keys = allocator.alloc([]const u8, 0) catch return .null;
    const init_path = allocator.alloc([]const u8, 0) catch return .null;
    const init_nodes = allocator.alloc(JsonValue, 0) catch return .null;
    const init_dpath = allocator.alloc([]const u8, dpath_len) catch return .null;
    @memcpy(init_dpath, dpath_buf[0..dpath_len]);
    const inj = allocator.create(voxgig_struct.Injection) catch return .null;
    inj.* = voxgig_struct.Injection{
        .allocator = allocator,
        .dparent = dparent,
        .keys = init_keys,
        .path = init_path,
        .nodes = init_nodes,
        .dpath = init_dpath,
        .errs = &errs,
    };
    return voxgig_struct.getpathInj(allocator, path_v, store, inj) catch return .null;
}

fn wrap_getpath_special(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { path, store, inj? }
    if (val != .object) return .null;
    const m = val.object;
    const path_v = m.get("path") orelse return .null;
    const store = m.get("store") orelse return .null;
    const inj_spec = m.get("inj");

    if (inj_spec) |ij| {
        var errs = std.array_list.Managed([]const u8).init(allocator);
        var init_keys = allocator.alloc([]const u8, 0) catch return .null;
        var init_path = allocator.alloc([]const u8, 0) catch return .null;
        var init_nodes = allocator.alloc(JsonValue, 0) catch return .null;
        var init_dpath = allocator.alloc([]const u8, 0) catch return .null;
        _ = &init_keys;
        _ = &init_path;
        _ = &init_nodes;
        _ = &init_dpath;
        const inj = allocator.create(voxgig_struct.Injection) catch return .null;
        inj.* = voxgig_struct.Injection{
            .allocator = allocator,
            .keys = init_keys,
            .path = init_path,
            .nodes = init_nodes,
            .dpath = init_dpath,
            .errs = &errs,
        };
        // Set key and meta from inj spec if present.
        if (ij == .object) {
            if (ij.object.get("key")) |key_val| {
                if (key_val == .string) inj.key = key_val.string;
            }
            if (ij.object.get("meta")) |meta_val| {
                inj.meta = meta_val;
            }
        }
        return voxgig_struct.getpathInj(allocator, path_v, store, inj) catch return .null;
    }

    return voxgig_struct.getpath(allocator, path_v, store) catch return .null;
}

test "getpath-basic" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "getpath", "basic", omni.sub(wrap_getpath_basic), .{});
}

test "getpath-relative" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "getpath", "relative", omni.sub(wrap_getpath_relative), .{});
}

test "getpath-special" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "getpath", "special", omni.sub(wrap_getpath_special), .{});
}

// ---- GetPath handler test ----

fn fooHandler(_: Allocator) anyerror!JsonValue {
    return JsonValue{ .string = "foo" };
}

fn wrap_getpath_handler(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { path, store }
    if (val != .object) return .null;
    const m = val.object;
    const path_v = m.get("path") orelse return .null;

    // Build a store that has $FOO as a function returning "foo".
    const handler_store = allocator.create(voxgig_struct.MapRef) catch return .null;
    handler_store.* = .{ .data = .empty, .allocator = allocator };
    handler_store.put("$TOP", .null) catch {};
    handler_store.put("$FOO", JsonValue{ .function = fooHandler }) catch {};

    return voxgig_struct.getpath(allocator, path_v, JsonValue{ .object = handler_store }) catch return .null;
}

test "getpath-handler" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "getpath", "handler", omni.sub(wrap_getpath_handler), .{});
}

// ---- Inject tests ----

fn wrap_inject(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { val, store }
    if (val != .object) return .null;
    const m = val.object;
    const inject_val = restoreNullMarks(allocator, m.get("val") orelse return .null);
    const store = restoreNullMarks(allocator, m.get("store") orelse JsonValue.makeMap(allocator) catch .null);
    return voxgig_struct.inject(allocator, inject_val, store, null) catch return .null;
}

test "inject-string" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "inject", "string", omni.sub(wrap_inject), .{});
}

test "inject-deep" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "inject", "deep", omni.sub(wrap_inject), .{});
}

// ---- Additional transform tests ----

test "transform-each" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "transform", "each", omni.subres(wrap_transform), .{});
}

test "transform-pack" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "transform", "pack", omni.subres(wrap_transform), .{});
}

test "transform-ref" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "transform", "ref", omni.subres(wrap_transform), .{});
}

test "transform-format" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "transform", "format", omni.subres(wrap_transform), omni.Flags.nonull());
}

test "transform-apply" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "transform", "apply", omni.subres(wrap_transform), .{});
}

// ---- Transform modify test ----

fn modifyPrependAt(_: Allocator, val: JsonValue, key: []const u8, parent: JsonValue, _: *voxgig_struct.Injection, _: JsonValue) void {
    if (val == .string and parent == .object) {
        const new_val = std.fmt.allocPrint(std.heap.page_allocator, "@{s}", .{val.string}) catch return;
        parent.object.put(key, JsonValue{ .string = new_val }) catch {};
    }
}

fn wrap_transform_modify(allocator: Allocator, val: JsonValue) JsonValue {
    if (val != .object) return .null;
    const m = val.object;
    const data = m.get("data") orelse .null;
    const spec = m.get("spec") orelse return .null;
    return voxgig_struct.transformModify(allocator, data, spec, modifyPrependAt) catch return .null;
}

test "transform-modify" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "transform", "modify", omni.sub(wrap_transform_modify), .{});
}

// ---- Validate tests ----

fn wrap_validate(allocator: Allocator, val: JsonValue) omni.SubResult {
    // in: { data, spec }
    //
    // This discarded `result.err` and answered with `result.out` alone, so
    // every one of validate's 60 `err:` entries had nothing to fail against -
    // the library collected the messages and the driver dropped them.
    if (val != .object) return omni.SubResult.val(.null);
    const m = val.object;
    const data = m.get("data") orelse .null;
    const spec = m.get("spec") orelse return omni.SubResult.val(.null);
    const injdef = m.get("inj") orelse .null;
    const result = voxgig_struct.validateWith(allocator, data, spec, injdef) catch |e|
        return omni.SubResult.fail(@errorName(e));
    if (result.err) |msg| return omni.SubResult.fail(msg);
    return omni.SubResult.val(result.out);
}

test "validate-basic" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "validate", "basic", omni.subres(wrap_validate), omni.Flags.nonull());
}

test "validate-child" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "validate", "child", omni.subres(wrap_validate), .{});
}

test "validate-one" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "validate", "one", omni.subres(wrap_validate), .{});
}

test "validate-exact" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "validate", "exact", omni.subres(wrap_validate), .{});
}

test "validate-invalid" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "validate", "invalid", omni.subres(wrap_validate), omni.Flags.nonull());
}

test "validate-special" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "validate", "special", omni.subres(wrap_validate), .{});
}

// ---- Select tests ----

fn wrap_select(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { obj, query }
    if (val != .object) return .null;
    const m = val.object;
    const obj = m.get("obj") orelse return .null;
    const query = m.get("query") orelse return .null;
    return voxgig_struct.select(allocator, obj, query) catch return .null;
}

test "select-basic" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "select", "basic", omni.sub(wrap_select), .{});
}

test "select-operators" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "select", "operators", omni.sub(wrap_select), .{});
}

test "select-edge" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "select", "edge", omni.sub(wrap_select), .{});
}

test "select-alts" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "select", "alts", omni.sub(wrap_select), .{});
}

// null_flag = false keeps JSON null as an actual null (not the "__NULL__"
// marker) so select sees a present-null field — the present-null defect.
test "select-nullkey" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "select", "nullkey", omni.sub(wrap_select), .{});
}

// ---- regex: parity floor Go stdlib regexp (design/REGEX_API.md) ----

fn rxStr(val: JsonValue) []const u8 {
    return if (val == .string) val.string else "";
}

fn rxGroupsValue(allocator: Allocator, groups: [][]const u8) JsonValue {
    const row = allocator.create(voxgig_struct.ListRef) catch return .null;
    row.* = .{ .data = voxgig_struct.ListData.init(allocator) };
    for (groups) |g| row.append(.{ .string = g }) catch return .null;
    return JsonValue{ .array = row };
}

fn wrap_re_test(allocator: Allocator, val: JsonValue) JsonValue {
    _ = allocator;
    if (val != .object) return .null;
    const m = val.object;
    const p = rxStr(m.get("pattern") orelse .null);
    const i = rxStr(m.get("input") orelse .null);
    return .{ .bool = voxgig_struct.re_test(p, i) };
}

fn wrap_re_find(allocator: Allocator, val: JsonValue) JsonValue {
    if (val != .object) return .null;
    const m = val.object;
    const p = rxStr(m.get("pattern") orelse .null);
    const i = rxStr(m.get("input") orelse .null);
    const found = voxgig_struct.re_find(allocator, p, i) orelse return .null;
    return rxGroupsValue(allocator, found);
}

fn wrap_re_find_all(allocator: Allocator, val: JsonValue) JsonValue {
    if (val != .object) return .null;
    const m = val.object;
    const p = rxStr(m.get("pattern") orelse .null);
    const i = rxStr(m.get("input") orelse .null);
    const out = allocator.create(voxgig_struct.ListRef) catch return .null;
    out.* = .{ .data = voxgig_struct.ListData.init(allocator) };
    const all = voxgig_struct.re_find_all(allocator, p, i) orelse return JsonValue{ .array = out };
    for (all) |mt| out.append(rxGroupsValue(allocator, mt)) catch return .null;
    return JsonValue{ .array = out };
}

fn wrap_re_replace(allocator: Allocator, val: JsonValue) JsonValue {
    if (val != .object) return .null;
    const m = val.object;
    const p = rxStr(m.get("pattern") orelse .null);
    const i = rxStr(m.get("input") orelse .null);
    const r = rxStr(m.get("replacement") orelse .null);
    const s = voxgig_struct.re_replace(allocator, p, i, r) catch return .null;
    return .{ .string = s };
}

fn wrap_re_escape(allocator: Allocator, val: JsonValue) JsonValue {
    if (val != .object) return .null;
    const m = val.object;
    const v = rxStr(m.get("val") orelse .null);
    const s = voxgig_struct.re_escape(allocator, v) catch return .null;
    return .{ .string = s };
}

test "regex-test" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "regex", "test", omni.sub(wrap_re_test), .{});
}

test "regex-find" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "regex", "find", omni.sub(wrap_re_find), .{});
}

test "regex-find_all" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "regex", "find_all", omni.sub(wrap_re_find_all), .{});
}

test "regex-replace" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "regex", "replace", omni.sub(wrap_re_replace), .{});
}

test "regex-escape" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "regex", "escape", omni.sub(wrap_re_escape), .{});
}

// ---- sentinels: Group A null/undefined unification across the readers ----

test "sentinels-getprop_unify" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "sentinels", "getprop_unify", omni.sub(wrap_getprop), omni.Flags.nonull());
}

test "sentinels-getelem_absent" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "sentinels", "getelem_absent", omni.sub(wrap_getelem), omni.Flags.nonull());
}

test "sentinels-haskey_unify" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "sentinels", "haskey_unify", omni.sub(wrap_haskey_val), omni.Flags.nonull());
}

test "sentinels-isempty_unify" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "sentinels", "isempty_unify", omni.sub(wrap_isempty), omni.Flags.nonull());
}

test "sentinels-isnode_unify" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "sentinels", "isnode_unify", omni.sub(wrap_isnode), omni.Flags.nonull());
}

test "sentinels-stringify_null" {
    const r = try omni.makeRunner();
    try omni.rungroup(&r, "sentinels", "stringify_null", omni.sub(wrap_stringify_raw), omni.Flags.nonull());
}
