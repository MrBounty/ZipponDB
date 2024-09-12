const std = @import("std");

pub fn build(b: *std.Build) void {
    // Build part
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "zippon",
        .root_source_file = b.path("src/dbconsole.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    // Run step
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Test step
    const tests1 = b.addTest(.{
        .root_source_file = b.path("src/parsers/data-parsing.zig"),
        .target = target,
        .optimize = optimize,
        .name = "Data parsing",
    });
    const run_tests1 = b.addRunArtifact(tests1);

    const tests2 = b.addTest(.{
        .root_source_file = b.path("src/tokenizers/cliTokenizer.zig"),
        .target = target,
        .optimize = optimize,
        .name = "CLI tokenizer",
    });
    const run_tests2 = b.addRunArtifact(tests2);

    const tests3 = b.addTest(.{
        .root_source_file = b.path("src/tokenizers/ziqlTokenizer.zig"),
        .target = target,
        .optimize = optimize,
        .name = "ZiQL tokenizer",
    });
    const run_tests3 = b.addRunArtifact(tests3);

    const tests4 = b.addTest(.{
        .root_source_file = b.path("src/tokenizers/schemaTokenizer.zig"),
        .target = target,
        .optimize = optimize,
        .name = "Schema tokenizer",
    });
    const run_tests4 = b.addRunArtifact(tests4);

    const tests5 = b.addTest(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
        .name = "ADD functions",
    });
    const run_tests5 = b.addRunArtifact(tests5);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests1.step);
    test_step.dependOn(&run_tests2.step);
    test_step.dependOn(&run_tests3.step);
    test_step.dependOn(&run_tests4.step);
    test_step.dependOn(&run_tests5.step);
}
