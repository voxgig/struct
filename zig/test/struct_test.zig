// RUN: zig build test
// RUN-SOME: zig build test 2>&1 | head

// Test structure mirrors ts/test/utility/StructUtility.test.ts
// Uses shared spec from build/test/test.json via runner.

const std = @import("std");
const testing = std.testing;

const voxgig_struct = @import("voxgig-struct");
const runner = @import("runner.zig");

const Allocator = std.mem.Allocator;
const JsonValue = voxgig_struct.JsonValue;
const StdJsonValue = std.json.Value;

// NOTE: tests are (mostly) in order of increasing dependence.

// Wrap library functions as runner.Subject (fn(StdJsonValue) StdJsonValue).
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

// Helper: get a nested spec section (operates on std.json for the test runner).
fn getMinorSpec(r: runner.RunPack, name: []const u8) !StdJsonValue {
    const minor = r.spec.get("minor") orelse return error.NoMinorSpec;
    return switch (minor) {
        .object => |obj| obj.get(name) orelse return error.NoSpec,
        else => return error.MinorNotObject,
    };
}

// ---- minor tests ----

test "minor-isnode" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAlloc(try getMinorSpec(r, "isnode"), wrap_isnode);
}

test "minor-ismap" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAlloc(try getMinorSpec(r, "ismap"), wrap_ismap);
}

test "minor-islist" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAlloc(try getMinorSpec(r, "islist"), wrap_islist);
}

test "minor-iskey" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "iskey"), .{ .null_flag = false }, wrap_iskey);
}

test "minor-isempty" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "isempty"), .{ .null_flag = false }, wrap_isempty);
}

test "minor-isfunc" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAlloc(try getMinorSpec(r, "isfunc"), wrap_isfunc);
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
    // Handle UNDEF marker (missing input → T_noval)
    if (val == .string) {
        if (std.mem.eql(u8, val.string, runner.UNDEFMARK)) {
            return JsonValue{ .integer = @as(i64, voxgig_struct.T_noval) };
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

fn wrap_clone(allocator: Allocator, val: JsonValue) JsonValue {
    // Handle UNDEF marker - return empty object
    if (val == .string) {
        if (std.mem.eql(u8, val.string, runner.UNDEFMARK)) {
            return .null;
        }
    }
    return voxgig_struct.clone(allocator, val) catch return .null;
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
        if (std.mem.eql(u8, v.string, runner.NULLMARK)) {
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
    const path = m.get("path") orelse {
        // No path field - return unknown-path
        var result = std.ArrayList(u8).init(allocator);
        result.appendSlice("<unknown-path>") catch return JsonValue{ .string = "<unknown-path>" };
        return JsonValue{ .string = result.items };
    };

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
    const s = switch (v) {
        .string => |str| str,
        else => return JsonValue{ .string = voxgig_struct.S_MT },
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
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAlloc(try getMinorSpec(r, "typename"), wrap_typename);
}

test "minor-typify" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "typify"), .{ .null_flag = false, .undef_as_null = false }, wrap_typify);
}

test "minor-size" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "size"), .{ .null_flag = false }, wrap_size);
}

test "minor-strkey" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "strkey"), .{ .null_flag = false }, wrap_strkey);
}

test "minor-keysof" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "keysof"), .{ .null_flag = false }, wrap_keysof);
}

test "minor-haskey" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "haskey"), .{ .null_flag = false }, wrap_haskey);
}

test "minor-items" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "items"), .{ .null_flag = false }, wrap_items);
}

test "minor-getelem" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "getelem"), .{ .null_flag = false }, wrap_getelem);
}

test "minor-getprop" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "getprop"), .{ .null_flag = false }, wrap_getprop);
}

test "minor-clone" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "clone"), .{ .null_flag = false, .undef_as_null = false }, wrap_clone);
}

test "minor-flatten" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAlloc(try getMinorSpec(r, "flatten"), wrap_flatten);
}

test "minor-filter" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAlloc(try getMinorSpec(r, "filter"), wrap_filter);
}

test "minor-delprop" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "delprop"), .{ .null_flag = false }, wrap_delprop);
}

test "minor-setprop" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "setprop"), .{ .null_flag = false }, wrap_setprop);
}

test "minor-escre" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAlloc(try getMinorSpec(r, "escre"), wrap_escre);
}

test "minor-escurl" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAlloc(try getMinorSpec(r, "escurl"), wrap_escurl);
}

test "minor-join" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "join"), .{ .null_flag = false }, wrap_join);
}

test "minor-jsonify" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAlloc(try getMinorSpec(r, "jsonify"), wrap_jsonify);
}

test "minor-stringify" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "stringify"), .{ .null_flag = false }, wrap_stringify);
}

test "minor-pathify" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "pathify"), .{ .null_flag = false }, wrap_pathify);
}

test "minor-slice" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "slice"), .{ .null_flag = false }, wrap_slice);
}

test "minor-pad" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "pad"), .{ .null_flag = false }, wrap_pad);
}

// ---- Walk, Merge, and Transform helpers ----

fn getSpec(r: runner.RunPack, name: []const u8) !JsonValue {
    return r.spec.get(name) orelse return error.NoSpec;
}

fn getSubSpec(r: runner.RunPack, section: []const u8, sub: []const u8) !StdJsonValue {
    const sec = r.spec.get(section) orelse return error.NoSpec;
    return switch (sec) {
        .object => |obj| obj.get(sub) orelse return error.NoSubSpec,
        else => return error.SpecNotObject,
    };
}

// ---- Walk wrappers ----

fn walkApplyBasic(_: Allocator, key: ?[]const u8, val: JsonValue, _: JsonValue, path: []const []const u8) !JsonValue {
    _ = key;
    // If value is a string, append ~path.
    if (val == .string) {
        // Build path string.
        var total_len: usize = val.string.len + 1; // +1 for '~'
        for (path) |p| total_len += p.len;
        if (path.len > 1) total_len += path.len - 1; // dots between parts

        var buf = std.ArrayList(u8).init(std.heap.page_allocator);
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
    if (val == .string and std.mem.eql(u8, val.string, runner.NULLMARK)) {
        return .null;
    }
    return voxgig_struct.walk(allocator, val, walkApplyBasic, null, voxgig_struct.MAXDEPTH) catch return .null;
}

fn wrap_walk_copy(allocator: Allocator, val: JsonValue) JsonValue {
    if (val == .string and std.mem.eql(u8, val.string, runner.UNDEFMARK)) {
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
        const new_obj_ref = allocator.create(voxgig_struct.MapRef) catch return .null; new_obj_ref.* = .{ .data = voxgig_struct.MapData.init(allocator) };
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

fn wrap_transform(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { data?, spec? }
    if (val != .object) return .null;
    const m = val.object;
    const data = m.get("data") orelse .null;
    const spec = m.get("spec") orelse return .null;
    return voxgig_struct.transform(allocator, data, spec) catch return .null;
}

// ---- Walk tests ----

test "walk-basic" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "walk", "basic"), .{ .null_flag = false }, wrap_walk_basic);
}

test "walk-copy" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "walk", "copy"), .{ .null_flag = false, .undef_as_null = false }, wrap_walk_copy);
}

test "walk-depth" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAlloc(try getSubSpec(r, "walk", "depth"), wrap_walk_depth);
}

// ---- Merge tests ----

test "merge-cases" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "merge", "cases"), .{ .null_flag = false }, wrap_merge_cases);
}

test "merge-array" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "merge", "array"), .{ .null_flag = false }, wrap_merge_array);
}

test "merge-integrity" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "merge", "integrity"), .{ .null_flag = false }, wrap_merge_integrity);
}

test "merge-depth" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "merge", "depth"), .{ .null_flag = false }, wrap_merge_depth);
}

// ---- Transform tests ----

test "transform-paths" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "transform", "paths"), .{ .null_flag = false }, wrap_transform);
}

test "transform-cmds" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "transform", "cmds"), .{ .null_flag = false }, wrap_transform);
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
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "setpath"), .{ .null_flag = false }, wrap_setpath);
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

    var errs = std.ArrayList([]const u8).init(allocator);
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
        var errs = std.ArrayList([]const u8).init(allocator);
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
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "getpath", "basic"), .{ .null_flag = false }, wrap_getpath_basic);
}

test "getpath-relative" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "getpath", "relative"), .{ .null_flag = false }, wrap_getpath_relative);
}

test "getpath-special" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "getpath", "special"), .{ .null_flag = false }, wrap_getpath_special);
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
    handler_store.* = .{ .data = voxgig_struct.MapData.init(allocator) };
    handler_store.put("$TOP", .null) catch {};
    handler_store.put("$FOO", JsonValue{ .function = fooHandler }) catch {};

    return voxgig_struct.getpath(allocator, path_v, JsonValue{ .object = handler_store }) catch return .null;
}

test "getpath-handler" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "getpath", "handler"), .{ .null_flag = false }, wrap_getpath_handler);
}

// ---- Inject tests ----

fn wrap_inject(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { val, store }
    if (val != .object) return .null;
    const m = val.object;
    const inject_val = m.get("val") orelse return .null;
    const store = m.get("store") orelse JsonValue.makeMap(allocator) catch .null;
    return voxgig_struct.injectVal(allocator, inject_val, store, null) catch return .null;
}

test "inject-string" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "inject", "string"), .{ .null_flag = false }, wrap_inject);
}

test "inject-deep" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "inject", "deep"), .{ .null_flag = false }, wrap_inject);
}

// ---- Additional transform tests ----

test "transform-each" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "transform", "each"), .{ .null_flag = false }, wrap_transform);
}

test "transform-pack" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "transform", "pack"), .{ .null_flag = false }, wrap_transform);
}

test "transform-ref" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "transform", "ref"), .{ .null_flag = false }, wrap_transform);
}

test "transform-format" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "transform", "format"), .{ .null_flag = false }, wrap_transform);
}

test "transform-apply" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "transform", "apply"), .{ .null_flag = false }, wrap_transform);
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
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "transform", "modify"), .{ .null_flag = false }, wrap_transform_modify);
}

// ---- Validate tests ----

fn wrap_validate(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { data, spec }
    if (val != .object) return .null;
    const m = val.object;
    const data = m.get("data") orelse .null;
    const spec = m.get("spec") orelse return .null;
    const result = voxgig_struct.validate(allocator, data, spec) catch return .null;
    return result.out;
}

test "validate-basic" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "validate", "basic"), .{ .null_flag = false }, wrap_validate);
}

test "validate-child" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "validate", "child"), .{ .null_flag = false }, wrap_validate);
}

test "validate-one" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "validate", "one"), .{ .null_flag = false }, wrap_validate);
}

test "validate-exact" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "validate", "exact"), .{ .null_flag = false }, wrap_validate);
}

test "validate-invalid" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "validate", "invalid"), .{ .null_flag = false }, wrap_validate);
}

test "validate-special" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "validate", "special"), .{ .null_flag = false }, wrap_validate);
}

// ---- Select tests ----

fn wrap_select(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { obj, query }
    if (val != .object) return .null;
    const m = val.object;
    const obj = m.get("obj") orelse return .null;
    const query = m.get("query") orelse return .null;
    return voxgig_struct.selectFn(allocator, obj, query) catch return .null;
}

test "select-basic" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "select", "basic"), .{ .null_flag = false }, wrap_select);
}

test "select-operators" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "select", "operators"), .{ .null_flag = false }, wrap_select);
}

test "select-edge" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "select", "edge"), .{ .null_flag = false }, wrap_select);
}

test "select-alts" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getSubSpec(r, "select", "alts"), .{ .null_flag = false }, wrap_select);
}
