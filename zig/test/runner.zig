// Test runner for Zig — loads build/test/test.json and drives specs
// against subject functions, mirroring the TS/Go runner pattern.

const std = @import("std");
const voxgig_struct = @import("voxgig-struct");

const Allocator = std.mem.Allocator;
const StdJsonValue = std.json.Value;
const JsonValue = voxgig_struct.JsonValue;

pub const NULLMARK = "__NULL__";
pub const UNDEFMARK = "__UNDEF__";
pub const EXISTSMARK = "__EXISTS__";

pub const TEST_JSON_FILE = "../build/test/test.json";

// Subject that takes only a std.json.Value (for simple is* functions).
pub const Subject = *const fn (StdJsonValue) StdJsonValue;

// Subject that takes an allocator and our JsonValue type.
pub const AllocSubject = *const fn (Allocator, JsonValue) JsonValue;

pub const Spec = struct {
    data: StdJsonValue,

    pub fn get(self: Spec, key: []const u8) ?StdJsonValue {
        return switch (self.data) {
            .object => |obj| obj.get(key),
            else => null,
        };
    }
};

pub const RunPack = struct {
    spec: Spec,
    allocator: Allocator,
    file_data: []const u8,
    parsed: std.json.Parsed(StdJsonValue),

    /// Run all entries in testspec.set against the subject function (no alloc, std types).
    pub fn runset(self: RunPack, testspec: StdJsonValue, subject: Subject) !void {
        try self.runsetflags(testspec, .{}, subject);
    }

    /// Run with flags (e.g. .{ .null_flag = false }).
    pub fn runsetflags(self: RunPack, testspec: StdJsonValue, flags: Flags, subject: Subject) !void {
        _ = self;
        const set = switch (testspec) {
            .object => |obj| obj.get("set") orelse return error.NoSetInSpec,
            else => return error.SpecNotObject,
        };
        const entries = switch (set) {
            .array => |arr| arr.items,
            else => return error.SetNotArray,
        };

        for (entries) |entry_val| {
            const entry = switch (entry_val) {
                .object => |obj| obj,
                else => continue,
            };

            const in_val: StdJsonValue = entry.get("in") orelse .null;
            const raw_out = entry.get("out");
            const expected: StdJsonValue = if (raw_out) |o| o else if (flags.null_flag) StdJsonValue{ .string = NULLMARK } else .null;
            const err_field = entry.get("err");

            const result = subject(in_val);
            if (err_field != null) continue;
            try checkResult(expected, result);
        }
    }

    /// Run all entries against an allocator-aware subject (uses our JsonValue type).
    pub fn runsetAlloc(self: RunPack, testspec: StdJsonValue, subject: AllocSubject) !void {
        try self.runsetAllocFlags(testspec, .{}, subject);
    }

    /// Run with flags against an allocator-aware subject.
    pub fn runsetAllocFlags(self: RunPack, testspec: StdJsonValue, flags: Flags, subject: AllocSubject) !void {
        const set = switch (testspec) {
            .object => |obj| obj.get("set") orelse return error.NoSetInSpec,
            else => return error.SpecNotObject,
        };
        const entries = switch (set) {
            .array => |arr| arr.items,
            else => return error.SetNotArray,
        };

        for (entries, 0..) |entry_val, entry_idx| {
            const entry = switch (entry_val) {
                .object => |obj| obj,
                else => continue,
            };

            const has_in = entry.get("in") != null;
            const in_val_std: StdJsonValue = entry.get("in") orelse
                if (flags.undef_as_null) .null else StdJsonValue{ .string = UNDEFMARK };

            const raw_out = entry.get("out");
            const expected: StdJsonValue = if (raw_out) |o| o else if (flags.null_flag) StdJsonValue{ .string = NULLMARK } else .null;

            const err_field = entry.get("err");
            _ = has_in;

            // Use an arena allocator for each test case.
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();
            const alloc = arena.allocator();

            // Convert std.json input to our JsonValue type.
            const in_val = voxgig_struct.fromStdJson(alloc, in_val_std) catch .null;

            const result_jval = subject(alloc, in_val);

            if (err_field != null) continue;

            // Convert our result back to std.json for comparison.
            const result = voxgig_struct.toStdJson(alloc, result_jval) catch StdJsonValue{ .null = {} };

            checkResult(expected, result) catch |e| {
                std.debug.print("  [test entry {d}]\n", .{entry_idx});
                return e;
            };
        }
    }

    pub fn deinit(self: *RunPack) void {
        self.parsed.deinit();
        self.allocator.free(self.file_data);
    }
};

pub const Flags = struct {
    null_flag: bool = true,
    undef_as_null: bool = true,
};

/// Load test.json and return the "struct" spec.
pub fn makeRunner(allocator: Allocator) !RunPack {
    const path = TEST_JSON_FILE;
    const data = try std.fs.cwd().readFileAlloc(allocator, path, 10 * 1024 * 1024);
    const parsed = try std.json.parseFromSlice(StdJsonValue, allocator, data, .{});
    const root = parsed.value;

    const spec_val = switch (root) {
        .object => |obj| obj.get("struct") orelse return error.NoStructInTestJson,
        else => return error.TestJsonNotObject,
    };

    return RunPack{
        .spec = Spec{ .data = spec_val },
        .allocator = allocator,
        .file_data = data,
        .parsed = parsed,
    };
}

// ---- Result comparison (operates on std.json.Value) ----

fn checkResult(expected: StdJsonValue, result: StdJsonValue) !void {
    if (jsonEqual(expected, result)) return;

    if (expected == .string) {
        if (std.mem.eql(u8, expected.string, NULLMARK)) {
            if (result == .null) return;
        }
    }

    std.debug.print("\n  FAIL: expected {s} got {s}\n", .{
        fmtJson(expected),
        fmtJson(result),
    });
    return error.ResultMismatch;
}

fn fmtJson(val: StdJsonValue) []const u8 {
    // Best-effort one-line representation for diagnostic output. Uses the
    // process-wide page allocator so the lifetime is OK for a print-and-die.
    var buf = std.ArrayList(u8).init(std.heap.page_allocator);
    std.json.stringify(val, .{}, buf.writer()) catch return "?";
    return buf.items;
}

/// Deep equality for std.json.Value.
pub fn jsonEqual(a: StdJsonValue, b: StdJsonValue) bool {
    const TagType = std.meta.Tag(StdJsonValue);
    const tag_a: TagType = a;
    const tag_b: TagType = b;

    // Allow integer/float cross-comparison for numeric equality.
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
                if (!jsonEqual(ai, bi)) return false;
            }
            return true;
        },
        .object => |av| {
            const bv = b.object;
            if (av.count() != bv.count()) return false;
            var it = av.iterator();
            while (it.next()) |kv| {
                const bval = bv.get(kv.key_ptr.*) orelse return false;
                if (!jsonEqual(kv.value_ptr.*, bval)) return false;
            }
            return true;
        },
    };
}
