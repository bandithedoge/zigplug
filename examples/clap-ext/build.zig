const std = @import("std");
const zigplug = @import("zigplug");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zigplug_dep = b.dependency("zigplug", .{
        .target = target,
        .optimize = optimize,
    });

    const plugin = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/Plugin.zig"),
        .imports = &.{
            .{ .name = "zigplug", .module = zigplug_dep.module("zigplug") },
            .{ .name = "zigplug_clap", .module = zigplug.clapModule(b, target, optimize) },
        },
    });

    _ = try zigplug.addClap(b, .{
        .name = "clap-ext",
        .root_module = plugin,
    });
}
