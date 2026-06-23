// Smoke test for the Zig test-provider port. Prints a small summary of the
// loaded corpus so the numbers can be eyeballed against the canonical target:
//
//   functions: minor, getpath, inject, merge, transform, walk, validate,
//              select, sentinels
//   total entries: 1325
//   expect kinds: value=1181, absent=84, match=1, error=59
//   input  kinds: in=1325
//   getpath/basic[0]: id=getpath/basic#deep, doc=true, input.kind=in,
//                     expect.kind=value, expect.value=42
//
// Run (Zig 0.13): from test/proto/zig/  ->  zig run smoke.zig
// (No build.zig needed; provider.zig is a plain stdlib-only module.)

const std = @import("std");
const provider = @import("provider.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const g0 = gpa.allocator();

    // Use an arena for all transient provider output (function/group/entry
    // slices), freed at the end.
    var arena = std.heap.ArenaAllocator.init(g0);
    defer arena.deinit();
    const a = arena.allocator();

    const stdout = std.io.getStdOut().writer();

    var tp = try provider.TestProvider.load(g0, null);
    defer tp.deinit();

    // ── functions list ──
    const fns = try tp.functions(a);
    try stdout.writeAll("functions: ");
    for (fns, 0..) |f, i| {
        if (i != 0) try stdout.writeAll(", ");
        try stdout.writeAll(f);
    }
    try stdout.writeAll("\n");

    // ── totals + expect/input kind counts ──
    var total: usize = 0;
    var ev: usize = 0; // value
    var ea: usize = 0; // absent
    var em: usize = 0; // match
    var ee: usize = 0; // error
    var ii: usize = 0; // input .in
    var ia: usize = 0; // input .args
    var ic: usize = 0; // input .ctx

    for (fns) |f| {
        const es = try tp.entries(a, f);
        total += es.len;
        for (es) |e| {
            switch (e.expect.kind) {
                .value => ev += 1,
                .absent => ea += 1,
                .match => em += 1,
                .error_ => ee += 1,
            }
            switch (e.input.kind) {
                .in => ii += 1,
                .args => ia += 1,
                .ctx => ic += 1,
            }
        }
    }

    try stdout.print("total entries: {d}\n", .{total});
    try stdout.print("expect kinds: value={d}, absent={d}, match={d}, error={d}\n", .{ ev, ea, em, ee });
    try stdout.print("input kinds: in={d}", .{ii});
    if (ia != 0) try stdout.print(", args={d}", .{ia});
    if (ic != 0) try stdout.print(", ctx={d}", .{ic});
    try stdout.writeAll("\n");

    // ── getpath/basic[0] spotlight ──
    const gb = try tp.entriesGroup(a, "getpath", "basic");
    if (gb.len > 0) {
        const e = gb[0];
        const id = e.id orelse "<null>";
        try stdout.print("getpath/basic[0]: id={s}, doc={}, input.kind={s}, expect.kind={s}, expect.value=", .{
            id,
            e.doc,
            @tagName(e.input.kind),
            expectKindName(e.expect.kind),
        });
        if (e.expect.value) |v| {
            try printValue(stdout, v);
        } else {
            try stdout.writeAll("<none>");
        }
        try stdout.writeAll("\n");
    } else {
        try stdout.writeAll("getpath/basic[0]: <no entries>\n");
    }
}

fn expectKindName(k: provider.ExpectKind) []const u8 {
    return switch (k) {
        .value => "value",
        .error_ => "error",
        .match => "match",
        .absent => "absent",
    };
}

fn printValue(writer: anytype, v: std.json.Value) !void {
    switch (v) {
        .integer => |n| try writer.print("{d}", .{n}),
        .float => |n| try writer.print("{d}", .{n}),
        .string => |s| try writer.writeAll(s),
        .bool => |b| try writer.print("{}", .{b}),
        .null => try writer.writeAll("null"),
        else => try std.json.stringify(v, .{}, writer),
    }
}
