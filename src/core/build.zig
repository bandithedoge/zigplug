const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("zigplug", .{
        .root_source_file = b.path("root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{
            .name = "msgpack",
            .module = b.dependency("msgpack", .{
                .target = target,
                .optimize = optimize,
            }).module("msgpack"),
        }},
    });

    const test_step = b.step("test", "Run unit tests");
    const tests = b.addTest(.{
        .root_module = module,
    });
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);

    const lib = b.addLibrary(.{
        .name = "zigplug_core",
        .root_module = module,
    });

    b.addNamedLazyPath("docs", lib.getEmittedDocs());

    const check = b.step("check", "Check compile errors");
    check.dependOn(&lib.step);
}
