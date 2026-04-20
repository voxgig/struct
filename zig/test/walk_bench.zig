// Benchmark for walk() on wide and deep trees. Mirrors ts/test/walk-bench.test.ts.
// Not run by default. To enable, set WALK_BENCH=1 in the environment.
//
// Run with:   WALK_BENCH=1 zig build bench
// Or:         WALK_BENCH=1 zig build test-bench

const std = @import("std");
const voxgig_struct = @import("voxgig-struct");

const Allocator = std.mem.Allocator;
const JsonValue = voxgig_struct.JsonValue;

// Build a balanced tree of maps with the given width and depth.
// Total nodes: (width^(depth+1) - 1) / (width - 1).
fn buildTree(allocator: Allocator, width: usize, depth: usize) anyerror!JsonValue {
    if (depth == 0) {
        return JsonValue{ .integer = 0 };
    }
    const out = try JsonValue.makeMap(allocator);
    var i: usize = 0;
    while (i < width) : (i += 1) {
        const key = try std.fmt.allocPrint(allocator, "k{d}", .{i});
        const child = try buildTree(allocator, width, depth - 1);
        try out.object.put(key, child);
    }
    return out;
}

fn countNodes(val: JsonValue) u64 {
    if (val != .object and val != .array) return 1;
    var n: u64 = 1;
    if (val == .object) {
        var it = val.object.data.iterator();
        while (it.next()) |kv| n += countNodes(kv.value_ptr.*);
    } else if (val == .array) {
        for (val.array.data.items) |item| n += countNodes(item);
    }
    return n;
}

// Minimal consumer: sum path length at each visit.
var bench_sink: u64 = 0;

fn benchCb(_: Allocator, _: ?[]const u8, val: JsonValue, _: JsonValue, path: []const []const u8) anyerror!JsonValue {
    bench_sink +%= path.len;
    return val;
}

fn u64LessThan(_: void, a: u64, b: u64) bool {
    return a < b;
}

fn measure(allocator: Allocator, label: []const u8, tree: JsonValue, runs: usize) !void {
    // Warm-up.
    var w: usize = 0;
    while (w < 2) : (w += 1) {
        _ = try voxgig_struct.walk(allocator, tree, benchCb, null, voxgig_struct.MAXDEPTH);
    }

    var times = try std.ArrayList(u64).initCapacity(allocator, runs);
    defer times.deinit();

    var r: usize = 0;
    while (r < runs) : (r += 1) {
        var timer = try std.time.Timer.start();
        _ = try voxgig_struct.walk(allocator, tree, benchCb, null, voxgig_struct.MAXDEPTH);
        const elapsed_ns = timer.read();
        try times.append(elapsed_ns);
    }

    std.mem.sort(u64, times.items, {}, u64LessThan);
    const median_ns = times.items[times.items.len / 2];
    const min_ns = times.items[0];
    const max_ns = times.items[times.items.len - 1];
    var sum: u128 = 0;
    for (times.items) |t| sum += t;
    const mean_ns: u64 = @intCast(sum / times.items.len);

    const nodes = countNodes(tree);
    const ns_per_node_x10: u64 = if (nodes > 0) (median_ns * 10) / nodes else 0;

    std.debug.print(
        "[walk-bench] {s}: nodes={d} runs={d} min={d:.2}ms median={d:.2}ms mean={d:.2}ms max={d:.2}ms ns/node={d}.{d} sink={d}\n",
        .{
            label,
            nodes,
            runs,
            @as(f64, @floatFromInt(min_ns)) / 1e6,
            @as(f64, @floatFromInt(median_ns)) / 1e6,
            @as(f64, @floatFromInt(mean_ns)) / 1e6,
            @as(f64, @floatFromInt(max_ns)) / 1e6,
            ns_per_node_x10 / 10,
            ns_per_node_x10 % 10,
            bench_sink,
        },
    );
}

fn benchEnabled() bool {
    const val = std.process.getEnvVarOwned(std.heap.page_allocator, "WALK_BENCH") catch return false;
    defer std.heap.page_allocator.free(val);
    return std.mem.eql(u8, val, "1");
}

test "walk-bench-wide-and-deep" {
    if (!benchEnabled()) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tree = try buildTree(allocator, 8, 6);
    try measure(allocator, "wide+deep (w=8,d=6)", tree, 7);
}

test "walk-bench-very-wide" {
    if (!benchEnabled()) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tree = try buildTree(allocator, 1000, 2);
    try measure(allocator, "wide (w=1000,d=2)", tree, 7);
}

test "walk-bench-very-deep" {
    if (!benchEnabled()) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tree = try buildTree(allocator, 2, 20);
    try measure(allocator, "deep (w=2,d=20)", tree, 5);
}
