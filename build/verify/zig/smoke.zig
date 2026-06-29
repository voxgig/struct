// Smoke client for the PUBLISHED Zig port, built against the source vendored
// from the git tag zig/v<VERSION>. The Makefile runs this with the vendored
// zig/src/struct.zig wired in as the `voxgig-struct` module, e.g.
//   zig run smoke.zig --dep voxgig-struct \
//     -Mroot=smoke.zig -Mvoxgig-struct=<topdir>/zig/src/struct.zig

const std = @import("std");
const struct_lib = @import("voxgig-struct");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // store = { db: { host: "localhost" } }
    // (Short-lived smoke: the GeneralPurposeAllocator backs everything and
    // is released at process exit, so we don't deep-free the tree here.)
    const root = try struct_lib.JsonValue.makeMap(allocator);

    const db = try struct_lib.JsonValue.makeMap(allocator);
    try db.object.put("host", .{ .string = "localhost" });
    try root.object.put("db", db);

    const path = struct_lib.JsonValue{ .string = "db.host" };
    const got = try struct_lib.getpath(allocator, path, root);

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    switch (got) {
        .string => |s| {
            if (std.mem.eql(u8, s, "localhost")) {
                try stdout.print("OK zig: getpath(db.host) = localhost\n", .{});
                std.process.exit(0);
            }
            try stderr.print("FAIL zig: getpath(db.host) = {s} (want localhost)\n", .{s});
            std.process.exit(1);
        },
        else => {
            try stderr.print("FAIL zig: getpath(db.host) is non-string (want localhost)\n", .{});
            std.process.exit(1);
        },
    }
}
