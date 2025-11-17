const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core = b.dependency("core", .{
        .target = target,
        .optimize = optimize,
    });

    const clap = b.dependency("clap", .{
        .target = target,
        .optimize = optimize,
    });

    const module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("root.zig"),
        .imports = &.{
            .{ .name = "zigplug", .module = core.module("zigplug") },
            .{ .name = "clap", .module = clap.module("clap") },
        },
    });

    const lib = b.addLibrary(.{
        .name = "zigplug_docs",
        .root_module = module,
    });

    b.installDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
}
