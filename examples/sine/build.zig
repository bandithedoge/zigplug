const std = @import("std");
const zigplug = @import("zigplug");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zigplug_dep = b.dependency("zigplug", .{
        .clap = true,
    });

    const plugin = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/Plugin.zig"),
        .imports = &.{
            .{ .name = "zigplug", .module = zigplug_dep.module("zigplug") },
            .{ .name = "zigplug_clap", .module = zigplug_dep.module("clap") },
        },
    });

    _ = try zigplug.addClap(b, .{
        .name = "sine",
        .root_module = plugin,
        .zigplug_dep = zigplug_dep,
    });
}
