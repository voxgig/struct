const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // mvzr regex dependency
    const mvzr_dep = b.dependency("mvzr", .{
        .target = target,
        .optimize = optimize,
    });
    const mvzr_mod = mvzr_dep.module("mvzr");

    // Library module
    const lib_mod = b.addModule("voxgig-struct", .{
        .root_source_file = b.path("src/struct.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_mod.addImport("mvzr", mvzr_mod);

    // Static library artifact
    const lib = b.addStaticLibrary(.{
        .name = "voxgig-struct",
        .root_source_file = b.path("src/struct.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    // Tests
    const tests = b.addTest(.{
        .root_source_file = b.path("test/struct_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.root_module.addImport("voxgig-struct", lib_mod);

    const run_tests = b.addRunArtifact(tests);
    run_tests.has_side_effects = true;

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    // Walk benchmarks — gated on the WALK_BENCH=1 env var at runtime.
    const bench = b.addTest(.{
        .root_source_file = b.path("test/walk_bench.zig"),
        .target = target,
        .optimize = optimize,
    });
    bench.root_module.addImport("voxgig-struct", lib_mod);

    const run_bench = b.addRunArtifact(bench);
    run_bench.has_side_effects = true;

    const bench_step = b.step("bench", "Run walk benchmark (requires WALK_BENCH=1)");
    bench_step.dependOn(&run_bench.step);
}
