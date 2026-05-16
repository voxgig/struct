// Discovery test: pathological regex inputs run against the port's re_* API.
// Goal is to surface failures across ports, not to assert behaviour.
// Panel is the same in every port (see REGEX.md).
//
// Zig's public regex surface currently exposes only re_compile/re_test/re_escape
// (see src/struct.zig). The find/replace/find_all cases below mark themselves
// as N/A — that absence is itself part of the discovery.

const std = @import("std");
const voxgig_struct = @import("voxgig-struct");

fn record_test(label: []const u8, ok: bool, ms: f64, value: anytype) void {
    const T = @TypeOf(value);
    const writer = std.io.getStdOut().writer();
    if (ok) {
        if (T == bool) {
            writer.print("[regex-discovery] {s} | {d:.2}ms | OK | {}\n", .{ label, ms, value }) catch {};
        } else {
            writer.print("[regex-discovery] {s} | {d:.2}ms | OK | {any}\n", .{ label, ms, value }) catch {};
        }
    } else {
        writer.print("[regex-discovery] {s} | {d:.2}ms | ERR | compile or run failed\n", .{ label, ms }) catch {};
    }
}

test "regex pathological discovery" {
    var buf: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = fba.allocator();

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

    // P1
    var t0 = std.time.nanoTimestamp();
    const b1 = voxgig_struct.re_test("^(a+)+$", p1_in);
    var ms = @as(f64, @floatFromInt(std.time.nanoTimestamp() - t0)) / 1e6;
    record_test("P1_redos_nested_plus", true, ms, b1);

    // P2
    t0 = std.time.nanoTimestamp();
    const b2 = voxgig_struct.re_test("^(a|aa)+$", p1_in);
    ms = @as(f64, @floatFromInt(std.time.nanoTimestamp() - t0)) / 1e6;
    record_test("P2_redos_alt_overlap", true, ms, b2);

    // P3, P4, P5, P10 — replace/find/find_all not in zig public surface.
    const writer = std.io.getStdOut().writer();
    try writer.print("[regex-discovery] P3_empty_repeat_replace | -.--ms | N/A | re_replace not exposed\n", .{});
    try writer.print("[regex-discovery] P4_unicode_replace_dot | -.--ms | N/A | re_replace not exposed\n", .{});
    try writer.print("[regex-discovery] P5_unicode_find_codepoint | -.--ms | N/A | re_find not exposed\n", .{});

    // P6
    t0 = std.time.nanoTimestamp();
    const b6 = voxgig_struct.re_test(nest40, "a");
    ms = @as(f64, @floatFromInt(std.time.nanoTimestamp() - t0)) / 1e6;
    record_test("P6_deep_nesting_compile", true, ms, b6);

    // P7
    t0 = std.time.nanoTimestamp();
    const b7 = voxgig_struct.re_test("^a{0,10000}b$", "aaaaaaaaaab");
    ms = @as(f64, @floatFromInt(std.time.nanoTimestamp() - t0)) / 1e6;
    record_test("P7_big_bounded_quantifier", true, ms, b7);

    // P8
    t0 = std.time.nanoTimestamp();
    const p8 = voxgig_struct.re_compile("[abc");
    ms = @as(f64, @floatFromInt(std.time.nanoTimestamp() - t0)) / 1e6;
    if (p8 == null) {
        try writer.print("[regex-discovery] P8_invalid_pattern | {d:.2}ms | ERR | compile returned null\n", .{ms});
    } else {
        try writer.print("[regex-discovery] P8_invalid_pattern | {d:.2}ms | OK | \"compiled\"\n", .{ms});
    }

    // P9
    t0 = std.time.nanoTimestamp();
    const b9 = voxgig_struct.re_test("^(a+)\\1$", "aaaa");
    ms = @as(f64, @floatFromInt(std.time.nanoTimestamp() - t0)) / 1e6;
    record_test("P9_backref_re2_forbidden", true, ms, b9);

    try writer.print("[regex-discovery] P10_find_all_zero_width | -.--ms | N/A | re_find_all not exposed\n", .{});
}
