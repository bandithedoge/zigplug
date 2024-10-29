const std = @import("std");
const zigplug = @import("zigplug");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const plugin = zigplug.Plugin.new(b, .{
        .name = "zigplug_example",
        .target = target,
        .optimize = optimize,
        .source_file = b.path("src/plugin.zig"),
    });

    _ = try plugin.addClapTarget();
}
