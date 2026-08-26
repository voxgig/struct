const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library module. Regex engine is vendored in-tree (src/regex.zig)
    // so there are no third-party package dependencies.
    const lib_mod = b.addModule("voxgig-struct", .{
        .root_source_file = b.path("src/struct.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Static library artifact. Since 0.14 every compile step takes a
    // *Module rather than a root source file, so the module above is the
    // artifact's root instead of being declared twice.
    const lib = b.addLibrary(.{
        .name = "voxgig-struct",
        .linkage = .static,
        .root_module = lib_mod,
    });
    b.installArtifact(lib);

    // The corpus runner is voxgig/omni, a local checkout. Its path arrives as
    // a build option because a Cargo-style literal path cannot read
    // $OMNI_HOME; the Makefile resolves the checkout and passes it. Nothing
    // here is declared in build.zig.zon and the library module never sees it,
    // so no consumer of this package resolves omni (register 4.13).
    const omni_path = b.option(
        []const u8,
        "omni",
        "Path to voxgig/omni's zig source (test only; set by the Makefile)",
    );

    // Each test/bench binary gets its own module: a Module carries the
    // target and optimize settings that used to sit on the compile step.
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/struct_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tests.root_module.addImport("voxgig-struct", lib_mod);
    if (omni_path) |op| {
        const omni_mod = b.createModule(.{
            .root_source_file = .{ .cwd_relative = op },
            .target = target,
            .optimize = optimize,
        });
        tests.root_module.addImport("omni", omni_mod);
    }

    const run_tests = b.addRunArtifact(tests);
    run_tests.has_side_effects = true;

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    // Walk benchmarks — gated on the WALK_BENCH=1 env var at runtime.
    const bench = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/walk_bench.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    bench.root_module.addImport("voxgig-struct", lib_mod);

    const run_bench = b.addRunArtifact(bench);
    run_bench.has_side_effects = true;

    const bench_step = b.step("bench", "Run walk benchmark (requires WALK_BENCH=1)");
    bench_step.dependOn(&run_bench.step);

    // Cross-port performance bench (JSON to stdout). See build/bench/README.md.
    // Invoke with: zig build perfbench -Doptimize=ReleaseFast
    const perfbench = b.addExecutable(.{
        .name = "perfbench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/bench.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    perfbench.root_module.addImport("voxgig-struct", lib_mod);
    const run_perfbench = b.addRunArtifact(perfbench);
    run_perfbench.has_side_effects = true;
    const perfbench_step = b.step("perfbench", "Cross-port performance bench (JSON)");
    perfbench_step.dependOn(&run_perfbench.step);
}
