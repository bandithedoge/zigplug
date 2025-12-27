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
        .root_source_file = b.path("src/ClapExtExample.zig"),
        .imports = &.{
            .{ .name = "zigplug", .module = zigplug_dep.module("zigplug") },
        },
    });

    _ = try zigplug.addClap(b, .{
        .name = "clap-ext",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/entry_clap.zig"),
            .imports = &.{
                .{ .name = "ClapExtExample", .module = plugin },

                .{ .name = "zigplug_clap", .module = zigplug.clapModule(b, target, optimize) },
            },
        }),
    });
}
