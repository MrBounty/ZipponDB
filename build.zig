const std = @import("std");

pub fn build(b: *std.Build) void {
    // Exe
    // -----------------------------------------------
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    const exe = b.addExecutable(.{
        .name = "ZipponDB",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    // Libs
    // -----------------------------------------------
    exe.root_module.addImport("dtype", b.createModule(.{ .root_source_file = b.path("lib/types/out.zig") }));
    exe.root_module.addImport("config", b.createModule(.{ .root_source_file = b.path("lib/config.zig") }));
    exe.root_module.addImport("ZipponData", b.createModule(.{ .root_source_file = b.path("lib/zid.zig") }));

    // Run
    // -----------------------------------------------
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Test
    // -----------------------------------------------
    const tests1 = b.addTest(.{
        .root_source_file = b.path("src/stuffs/UUIDFileIndex.zig"),
        .target = target,
        .optimize = optimize,
        .name = "CLI tokenizer",
        .test_runner = b.path("test_runner.zig"),
    });
    tests1.root_module.addImport("dtype", b.createModule(.{ .root_source_file = b.path("lib/types/out.zig") }));
    const run_tests1 = b.addRunArtifact(tests1);

    const tests2 = b.addTest(.{
        .root_source_file = b.path("src/tokenizers/cli.zig"),
        .target = target,
        .optimize = optimize,
        .name = "CLI tokenizer",
        .test_runner = b.path("test_runner.zig"),
    });
    const run_tests2 = b.addRunArtifact(tests2);

    const tests3 = b.addTest(.{
        .root_source_file = b.path("src/tokenizers/ziql.zig"),
        .target = target,
        .optimize = optimize,
        .name = "ZiQL tokenizer",
        .test_runner = b.path("test_runner.zig"),
    });
    const run_tests3 = b.addRunArtifact(tests3);

    const tests4 = b.addTest(.{
        .root_source_file = b.path("src/tokenizers/schema.zig"),
        .target = target,
        .optimize = optimize,
        .name = "Schema tokenizer",
        .test_runner = b.path("test_runner.zig"),
    });
    tests4.root_module.addImport("config", b.createModule(.{ .root_source_file = b.path("lib/config.zig") }));
    tests4.root_module.addImport("dtype", b.createModule(.{ .root_source_file = b.path("lib/types/out.zig") }));
    const run_tests4 = b.addRunArtifact(tests4);

    const tests5 = b.addTest(.{
        .root_source_file = b.path("test.zig"),
        .target = target,
        .optimize = optimize,
        .name = "ZiQL parser",
        .test_runner = b.path("test_runner.zig"),
    });
    tests5.root_module.addImport("dtype", b.createModule(.{ .root_source_file = b.path("lib/types/out.zig") }));
    tests5.root_module.addImport("config", b.createModule(.{ .root_source_file = b.path("lib/config.zig") }));
    tests5.root_module.addImport("ZipponData", b.createModule(.{ .root_source_file = b.path("lib/zid.zig") }));
    const run_tests5 = b.addRunArtifact(tests5);

    const tests6 = b.addTest(.{
        .root_source_file = b.path("src/stuffs/filter.zig"),
        .target = target,
        .optimize = optimize,
        .name = "Filter tree",
        .test_runner = b.path("test_runner.zig"),
    });
    tests6.root_module.addImport("dtype", b.createModule(.{ .root_source_file = b.path("lib/types/out.zig") }));
    tests6.root_module.addImport("config", b.createModule(.{ .root_source_file = b.path("lib/config.zig") }));
    tests6.root_module.addImport("ZipponData", b.createModule(.{ .root_source_file = b.path("lib/zid.zig") }));
    const run_tests6 = b.addRunArtifact(tests6);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests1.step);
    test_step.dependOn(&run_tests2.step);
    test_step.dependOn(&run_tests3.step);
    test_step.dependOn(&run_tests4.step);
    test_step.dependOn(&run_tests5.step);
    test_step.dependOn(&run_tests6.step);

    // Benchmark
    // -----------------------------------------------
    const benchmark = b.addExecutable(.{
        .name = "benchmark",
        .root_source_file = b.path("benchmark.zig"),
        .target = target,
        .optimize = optimize,
    });
    benchmark.root_module.addImport("dtype", b.createModule(.{ .root_source_file = b.path("lib/types/out.zig") }));
    benchmark.root_module.addImport("config", b.createModule(.{ .root_source_file = b.path("lib/config.zig") }));
    benchmark.root_module.addImport("ZipponData", b.createModule(.{ .root_source_file = b.path("lib/zid.zig") }));
    b.installArtifact(benchmark);

    const run_benchmark = b.addRunArtifact(benchmark);
    run_benchmark.step.dependOn(b.getInstallStep());

    const benchmark_step = b.step("benchmark", "Run benchmarks");
    benchmark_step.dependOn(&run_benchmark.step);
}
