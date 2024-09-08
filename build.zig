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
    const cliTokenizer_tests = b.addTest(.{
        .root_source_file = b.path("src/tokenizers/cliTokenizer.zig"),
        .target = target,
        .optimize = optimize,
        .name = "CLID Tokenizer test",
    });
    const ziqlTokenizer_tests = b.addTest(.{
        .root_source_file = b.path("src/tokenizers/ziqlTokenizer.zig"),
        .target = target,
        .optimize = optimize,
        .name = "ZiQL Tokenizer test",
    });
    const run_cliTokenizer_tests = b.addRunArtifact(cliTokenizer_tests);
    const run_ziqlTokenizer_tests = b.addRunArtifact(ziqlTokenizer_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_cliTokenizer_tests.step);
    test_step.dependOn(&run_ziqlTokenizer_tests.step);
}
