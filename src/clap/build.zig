const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root = b.dependency("zigplug", .{
        .target = target,
        .optimize = optimize,
    });

    const clap_dep = b.dependency("clap_c", .{});

    const clap_c = b.addTranslateC(.{
        .root_source_file = clap_dep.path("include/clap/clap.h"),
        .target = target,
        .optimize = optimize,
    });

    const module = b.addModule("clap", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("root.zig"),
        .imports = &.{
            .{ .name = "zigplug", .module = root.module("zigplug") },
            .{ .name = "clap_c", .module = clap_c.createModule() },
        },
    });

    module.addImport("clap", module);

    const test_step = b.step("test", "Run unit tests");
    const tests = b.addTest(.{ .root_module = module });
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);

    const lib = b.addLibrary(.{
        .name = "zigplug_clap",
        .root_module = module,
    });

    b.addNamedLazyPath("docs", lib.getEmittedDocs());

    const check = b.step("check", "Check compile errors");
    check.dependOn(&lib.step);
}
