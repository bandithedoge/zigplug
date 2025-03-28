const std = @import("std");
const zigplug = @import("zigplug");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zigplug_dep = b.dependency("zigplug", .{
        .with_clap = true,
        .with_gui = true,
        .gui_backend = .gl,
    });

    const plugin = b.addLibrary(.{
        .name = "zigplug_opengl_example",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/Plugin.zig"),
            .imports = &.{
                .{ .name = "zigplug", .module = zigplug_dep.module("zigplug") },
            },
        }),
    });

    plugin.root_module.addImport("zigplug", zigplug_dep.module("zigplug"));

    const builder = zigplug.PluginBuilder.new(plugin, zigplug_dep);

    _ = try builder.addClapTarget();
}
