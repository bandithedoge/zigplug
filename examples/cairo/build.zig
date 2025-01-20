const std = @import("std");
const zigplug = @import("zigplug");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const plugin = b.addStaticLibrary(.{
        .name = "cairo_example",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/Plugin.zig"),
    });

    const zigplug_dep = b.dependency("zigplug", .{
        .with_clap = true,
        .with_gui = true,
        .gui_backend = .cairo,
    });

    // plugin.root_module.addImport("zigplug", zigplug_dep.module("zigplug"));

    const builder = zigplug.PluginBuilder.new(plugin, zigplug_dep);

    _ = try builder.addClapTarget();
}
