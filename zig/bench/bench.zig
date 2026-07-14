// Performance bench for the Zig port. Emits one JSON line to stdout per
// build/bench/README.md; diagnostics go to stderr. Each op gets its own arena
// (built inputs + per-run outputs), freed after the op, to bound memory.
const std = @import("std");
const builtin = @import("builtin");
const voxgig_struct = @import("voxgig-struct");

const Allocator = std.mem.Allocator;
const JsonValue = voxgig_struct.JsonValue;

var bench_sink: u64 = 0;

fn envi(k: []const u8, d: usize) usize {
    const v = std.process.getEnvVarOwned(std.heap.page_allocator, k) catch return d;
    defer std.heap.page_allocator.free(v);
    return std.fmt.parseInt(usize, v, 10) catch d;
}

fn buildTree(a: Allocator, w: usize, d: usize, leaf: i64) anyerror!JsonValue {
    if (d == 0) return JsonValue{ .integer = leaf };
    const out = try JsonValue.makeMap(a);
    var i: usize = 0;
    while (i < w) : (i += 1) {
        const key = try std.fmt.allocPrint(a, "k{d}", .{i});
        try out.object.put(key, try buildTree(a, w, d - 1, leaf));
    }
    return out;
}

fn nodecount(w: usize, d: usize) u64 {
    var n: u64 = 0;
    var p: u64 = 1;
    var i: usize = 0;
    while (i <= d) : (i += 1) {
        n += p;
        p *= w;
    }
    return n;
}

fn benchCb(_: Allocator, _: ?[]const u8, val: JsonValue, _: JsonValue, path: []const []const u8) anyerror!JsonValue {
    bench_sink +%= path.len;
    return val;
}

const Op = enum { clone, walk, merge, stringify, getpath };
const Stats = struct { min_ms: f64, median_ms: f64, mean_ms: f64 };

fn lt(_: void, a: u64, b: u64) bool {
    return a < b;
}

fn finish(times: []u64) Stats {
    std.mem.sort(u64, times, {}, lt);
    var sum: u64 = 0;
    for (times) |t| sum += t;
    const n = times.len;
    return .{
        .min_ms = @as(f64, @floatFromInt(times[0])) / 1e6,
        .median_ms = @as(f64, @floatFromInt(times[n / 2])) / 1e6,
        .mean_ms = @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(n)) / 1e6,
    };
}

fn doOp(a: Allocator, op: Op, tree: JsonValue, mlist: JsonValue, path: JsonValue, gp: usize) !void {
    switch (op) {
        .clone => _ = try voxgig_struct.clone(a, tree),
        .walk => _ = try voxgig_struct.walk(a, tree, benchCb, null, voxgig_struct.MAXDEPTH),
        .merge => _ = try voxgig_struct.merge(a, mlist, voxgig_struct.MAXDEPTH),
        .stringify => {
            const s = try voxgig_struct.stringify(a, tree, null);
            bench_sink +%= s.len;
        },
        .getpath => {
            var j: usize = 0;
            while (j < gp) : (j += 1) _ = try voxgig_struct.getpath(a, path, tree);
            bench_sink +%= gp;
        },
    }
}

fn runOp(base: Allocator, op: Op, w: usize, d: usize, warm: usize, runs: usize, gp: usize, times: []u64) !Stats {
    var arena = std.heap.ArenaAllocator.init(base);
    defer arena.deinit();
    const a = arena.allocator();

    const tree = try buildTree(a, w, d, 0);
    var mlist: JsonValue = undefined;
    var path: JsonValue = undefined;
    if (op == .merge) {
        mlist = try JsonValue.makeList(a);
        try mlist.array.append(try buildTree(a, w, d, 1));
        try mlist.array.append(try buildTree(a, w, d, 2));
    }
    if (op == .getpath) {
        var buf = std.ArrayList(u8).init(a);
        var i: usize = 0;
        while (i < d) : (i += 1) {
            if (i > 0) try buf.append('.');
            try buf.appendSlice("k0");
        }
        path = JsonValue{ .string = try buf.toOwnedSlice() };
    }

    var i: usize = 0;
    while (i < warm) : (i += 1) try doOp(a, op, tree, mlist, path, gp);
    i = 0;
    while (i < runs) : (i += 1) {
        var timer = try std.time.Timer.start();
        try doOp(a, op, tree, mlist, path, gp);
        times[i] = timer.read();
    }
    return finish(times);
}

pub fn main() !void {
    const base = std.heap.page_allocator;
    const w = envi("BENCH_WIDTH", 5);
    const d = envi("BENCH_DEPTH", 6);
    const warm = envi("BENCH_WARMUP", 3);
    const runs = envi("BENCH_RUNS", 21);
    const gp = envi("BENCH_GETPATH_ITERS", 2000);
    const nodes = nodecount(w, d);
    const times = try base.alloc(u64, runs);
    defer base.free(times);

    const specs = [_]struct { name: []const u8, op: Op, uc: u64 }{
        .{ .name = "clone", .op = .clone, .uc = nodes },
        .{ .name = "walk", .op = .walk, .uc = nodes },
        .{ .name = "merge", .op = .merge, .uc = nodes },
        .{ .name = "stringify", .op = .stringify, .uc = nodes },
        .{ .name = "getpath", .op = .getpath, .uc = @as(u64, gp) },
    };

    var out = std.ArrayList(u8).init(base);
    defer out.deinit();
    const wr = out.writer();
    try wr.print("{{\"lang\":\"zig\",\"runtime\":\"zig {s}\",\"nodes\":{d},\"params\":{{\"width\":{d},\"depth\":{d},\"warmup\":{d},\"runs\":{d},\"getpath_iters\":{d}}},\"ops\":[", .{ builtin.zig_version_string, nodes, w, d, warm, runs, gp });
    for (specs, 0..) |spec, idx| {
        const s = try runOp(base, spec.op, w, d, warm, runs, gp, times);
        if (idx > 0) try wr.writeByte(',');
        try wr.print("{{\"op\":\"{s}\",\"runs\":{d},\"unit_count\":{d},\"min_ms\":{d:.6},\"median_ms\":{d:.6},\"mean_ms\":{d:.6}}}", .{ spec.name, runs, spec.uc, s.min_ms, s.median_ms, s.mean_ms });
    }
    try wr.writeAll("]}\n");
    try std.io.getStdOut().writeAll(out.items);
    std.debug.print("zig: sink={d}\n", .{bench_sink});
}
