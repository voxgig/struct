// Discovery test: pathological regex inputs run against the port's re_* API.
// Goal is to surface failures across ports, not to assert behaviour.
// Panel is the same in every port (see REGEX.md).

const std = @import("std");
const voxgig_struct = @import("voxgig-struct");

fn ms_since(t0: i128) f64 {
    return @as(f64, @floatFromInt(std.time.nanoTimestamp() - t0)) / 1e6;
}

test "regex pathological discovery" {
    const writer = std.io.getStdOut().writer();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const a22 = try alloc.alloc(u8, 22);
    @memset(a22, 'a');
    const p1_in = try std.fmt.allocPrint(alloc, "{s}!", .{a22});

    var nest_buf: [120]u8 = undefined;
    var pos: usize = 0;
    while (pos < 40) : (pos += 1) nest_buf[pos] = '(';
    nest_buf[pos] = 'a';
    pos += 1;
    var i: usize = 0;
    while (i < 40) : (i += 1) {
        nest_buf[pos] = ')';
        pos += 1;
    }
    const nest40 = nest_buf[0..pos];

    var t0 = std.time.nanoTimestamp();
    const b1 = voxgig_struct.re_test("^(a+)+$", p1_in);
    try writer.print("[regex-discovery] P1_redos_nested_plus | {d:.2}ms | OK | {}\n", .{ ms_since(t0), b1 });

    t0 = std.time.nanoTimestamp();
    const b2 = voxgig_struct.re_test("^(a|aa)+$", p1_in);
    try writer.print("[regex-discovery] P2_redos_alt_overlap | {d:.2}ms | OK | {}\n", .{ ms_since(t0), b2 });

    t0 = std.time.nanoTimestamp();
    const p3 = try voxgig_struct.re_replace(alloc, "a*", "abc", "X");
    try writer.print("[regex-discovery] P3_empty_repeat_replace | {d:.2}ms | OK | \"{s}\"\n", .{ ms_since(t0), p3 });

    t0 = std.time.nanoTimestamp();
    const p4 = try voxgig_struct.re_replace(alloc, "\\.", "café.au.lait", "/");
    try writer.print("[regex-discovery] P4_unicode_replace_dot | {d:.2}ms | OK | \"{s}\"\n", .{ ms_since(t0), p4 });

    t0 = std.time.nanoTimestamp();
    if (voxgig_struct.re_find(alloc, "é", "café au lait")) |p5| {
        try writer.print("[regex-discovery] P5_unicode_find_codepoint | {d:.2}ms | OK | [\"{s}\"]\n", .{ ms_since(t0), p5[0] });
    } else {
        try writer.print("[regex-discovery] P5_unicode_find_codepoint | {d:.2}ms | OK | null\n", .{ms_since(t0)});
    }

    t0 = std.time.nanoTimestamp();
    const b6 = voxgig_struct.re_test(nest40, "a");
    try writer.print("[regex-discovery] P6_deep_nesting_compile | {d:.2}ms | OK | {}\n", .{ ms_since(t0), b6 });

    t0 = std.time.nanoTimestamp();
    const b7 = voxgig_struct.re_test("^a{0,10000}b$", "aaaaaaaaaab");
    try writer.print("[regex-discovery] P7_big_bounded_quantifier | {d:.2}ms | OK | {}\n", .{ ms_since(t0), b7 });

    t0 = std.time.nanoTimestamp();
    const p8 = voxgig_struct.re_compile("[abc");
    if (p8 == null) {
        try writer.print("[regex-discovery] P8_invalid_pattern | {d:.2}ms | ERR | compile returned null\n", .{ms_since(t0)});
    } else {
        try writer.print("[regex-discovery] P8_invalid_pattern | {d:.2}ms | OK | \"compiled\"\n", .{ms_since(t0)});
    }

    t0 = std.time.nanoTimestamp();
    const b9 = voxgig_struct.re_test("^(a+)\\1$", "aaaa");
    try writer.print("[regex-discovery] P9_backref_re2_forbidden | {d:.2}ms | OK | {}\n", .{ ms_since(t0), b9 });

    t0 = std.time.nanoTimestamp();
    if (voxgig_struct.re_find_all(alloc, "a*", "bbb")) |p10| {
        try writer.print("[regex-discovery] P10_find_all_zero_width | {d:.2}ms | OK | <{} matches>\n", .{ ms_since(t0), p10.len });
    } else {
        try writer.print("[regex-discovery] P10_find_all_zero_width | {d:.2}ms | OK | null\n", .{ms_since(t0)});
    }
}
