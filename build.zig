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
        .root_source_file = b.path("src/data-parsing.zig"),
        .target = target,
        .optimize = optimize,
        .name = "Data parsing",
    });
    const run_tests1 = b.addRunArtifact(tests1);

    const tests2 = b.addTest(.{
        .root_source_file = b.path("src/cliTokenizer.zig"),
        .target = target,
        .optimize = optimize,
        .name = "CLI tokenizer",
    });
    const run_tests2 = b.addRunArtifact(tests2);

    const tests3 = b.addTest(.{
        .root_source_file = b.path("src/ziqlTokenizer.zig"),
        .target = target,
        .optimize = optimize,
        .name = "ZiQL tokenizer",
    });
    const run_tests3 = b.addRunArtifact(tests3);

    const tests4 = b.addTest(.{
        .root_source_file = b.path("src/schemaTokenizer.zig"),
        .target = target,
        .optimize = optimize,
        .name = "Schema tokenizer",
    });
    const run_tests4 = b.addRunArtifact(tests4);

    //const tests5 = b.addTest(.{
    //    .root_source_file = b.path("src/ADD.zig"),
    //    .target = target,
    //    .optimize = optimize,
    //    .name = "ADD",
    //});
    //const run_tests5 = b.addRunArtifact(tests5);

    const tests6 = b.addTest(.{
        .root_source_file = b.path("src/GRAB.zig"),
        .target = target,
        .optimize = optimize,
        .name = "GRAB",
    });
    const run_tests6 = b.addRunArtifact(tests6);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests1.step);
    test_step.dependOn(&run_tests2.step);
    test_step.dependOn(&run_tests3.step);
    test_step.dependOn(&run_tests4.step);
    //test_step.dependOn(&run_tests5.step);
    test_step.dependOn(&run_tests6.step);
}
