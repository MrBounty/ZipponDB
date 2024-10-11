const std = @import("std");

pub fn build(b: *std.Build) void {
    // Build part
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "zippon",
        .root_source_file = b.path("src/cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    // Run step
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const tests1 = b.addTest(.{
        .root_source_file = b.path("src/tokenizers/file.zig"),
        .target = target,
        .optimize = optimize,
        .name = "File tokenizer",
        .test_runner = b.path("test_runner.zig"),
    });
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
    const run_tests4 = b.addRunArtifact(tests4);

    const tests5 = b.addTest(.{
        .root_source_file = b.path("src/types/uuid.zig"),
        .target = target,
        .optimize = optimize,
        .name = "UUID",
        .test_runner = b.path("test_runner.zig"),
    });
    const run_tests5 = b.addRunArtifact(tests5);

    const tests6 = b.addTest(.{
        .root_source_file = b.path("src/fileEngine.zig"),
        .target = target,
        .optimize = optimize,
        .name = "File Engine",
        .test_runner = b.path("test_runner.zig"),
    });
    const run_tests6 = b.addRunArtifact(tests6);

    const tests8 = b.addTest(.{
        .root_source_file = b.path("src/ziqlParser.zig"),
        .target = target,
        .optimize = optimize,
        .name = "ZiQL parser",
        .test_runner = b.path("test_runner.zig"),
    });
    const run_tests8 = b.addRunArtifact(tests8);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests1.step);
    test_step.dependOn(&run_tests2.step);
    test_step.dependOn(&run_tests3.step);
    test_step.dependOn(&run_tests4.step);
    test_step.dependOn(&run_tests5.step);
    test_step.dependOn(&run_tests6.step);
    test_step.dependOn(&run_tests8.step);
}
