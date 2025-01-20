const std = @import("std");
const zigplug = @import("zigplug");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const plugin = b.addStaticLibrary(.{
        .name = "zigplug_minimal",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/Plugin.zig"),
    });

    const zigplug_dep = b.dependency("zigplug", .{
        .with_clap = true,
    });

    const builder = zigplug.PluginBuilder.new(plugin, zigplug_dep);

    _ = try builder.addClapTarget();
}
