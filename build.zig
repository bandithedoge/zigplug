const std = @import("std");
const this = @This();

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options = .{
        .with_clap = b.option(bool, "with_clap", "Build CLAP target") orelse false,

        .with_gui = b.option(bool, "with_gui", "Build GUI") orelse false,
        .gui_backend = b.option(enum { external, gl, cairo }, "gui_backend", "GUI backend") orelse .gl,
    };

    const options_step = b.addOptions();
    inline for (std.meta.fields(@TypeOf(options))) |field| {
        options_step.addOption(field.type, field.name, @field(options, field.name));
    }
    const options_module = options_step.createModule();

    const zigplug = b.addModule("zigplug", .{
        .root_source_file = b.path("src/zigplug/zigplug.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigplug_options", .module = options_module },
        },
    });

    if (options.with_gui) {
        if (b.lazyDependency("pugl", .{})) |pugl_dep| {
            const pugl = b.addStaticLibrary(.{
                .name = "pugl",
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            });

            var pugl_sources = std.ArrayList([]const u8).init(b.allocator);
            try pugl_sources.appendSlice(&.{ "src/common.c", "src/internal.c" });
            switch (target.result.os.tag) {
                .linux => {
                    try pugl_sources.appendSlice(&.{ "src/x11.c", switch (options.gui_backend) {
                        .gl => "src/x11_gl.c",
                        .cairo => "src/x11_cairo.c",
                        else => unreachable,
                    } });
                    pugl.linkSystemLibrary("X11");

                    switch (options.gui_backend) {
                        .gl => zigplug.linkSystemLibrary("gl", .{}),
                        .cairo => {
                            if (b.lazyDependency("cairo", .{
                                .target = target,
                                .optimize = optimize,
                                .use_glib = false,
                                .use_xcb = false,
                                .use_zlib = false,
                                .symbol_lookup = false,
                            })) |cairo| {
                                const cairo_lib = cairo.artifact("cairo");
                                zigplug.linkLibrary(cairo_lib);
                                pugl.linkLibrary(cairo_lib);

                                const cairo_c = b.addTranslateC(.{
                                    .root_source_file = cairo_lib.getEmittedIncludeTree().path(cairo.builder, "cairo.h"),
                                    .target = target,
                                    .optimize = optimize,
                                });
                                zigplug.addImport("cairo_c", cairo_c.addModule("cairo_c"));
                            }
                        },
                        else => unreachable,
                    }
                },
                else => {
                    _ = @panic("GUI not supported on target OS");
                },
            }

            pugl.addIncludePath(pugl_dep.path("include"));
            zigplug.addIncludePath(pugl_dep.path("include"));

            pugl.addCSourceFiles(.{
                .root = pugl_dep.path(""),
                .files = try pugl_sources.toOwnedSlice(),
                .flags = &.{
                    "-DPUGL_STATIC",
                    "-DPUGL_DISABLE_DEPRECATED",
                },
            });
            zigplug.linkLibrary(pugl);
        }
    }

    if (options.with_clap) {
        const clap_adapter = b.addModule("clap_adapter", .{
            .root_source_file = b.path("src/clap/adapter.zig"),
            .imports = &.{
                .{ .name = "zigplug", .module = zigplug },
                .{ .name = "zigplug_options", .module = options_module },
            },
        });
        clap_adapter.addImport("clap_adapter", clap_adapter);

        if (b.lazyDependency("clap_api", .{})) |clap_dep| {
            const clap_c = b.addTranslateC(.{
                .root_source_file = clap_dep.path("include/clap/clap.h"),
                .target = target,
                .optimize = optimize,
            });
            clap_adapter.addAnonymousImport("clap_c", .{
                .root_source_file = clap_c.getOutput(),
            });
        }
    }
}

pub const PluginBuilder = struct {
    object: *std.Build.Step.Compile,
    zigplug: *std.Build.Dependency,

    pub fn new(object: *std.Build.Step.Compile, zigplug: *std.Build.Dependency) PluginBuilder {
        return .{
            .object = object,
            .zigplug = zigplug,
        };
    }

    pub fn addClapTarget(self: *const PluginBuilder) !*std.Build.Step.Compile {
        const b = self.zigplug.builder;

        const name = try std.mem.concat(b.allocator, u8, &[_][]const u8{ self.object.name, ".clap" });

        const entry = b.addWriteFile("clap_entry.zig",
            \\ export const clap_entry = @import("clap_adapter").clap_entry(@import("plugin_root"));
        );
        entry.step.dependOn(&self.object.step);

        const clap = b.addSharedLibrary(.{
            .name = name,
            .root_source_file = entry.getDirectory().path(b, "clap_entry.zig"),
            .target = self.object.root_module.resolved_target orelse b.standardTargetOptions(.{}),
            .optimize = self.object.root_module.optimize orelse b.standardOptimizeOption(.{}),
        });
        clap.step.dependOn(&entry.step);
        clap.root_module.addImport("plugin_root", &self.object.root_module);
        clap.root_module.addImport("clap_adapter", self.zigplug.module("clap_adapter"));

        const install = self.object.step.owner.addInstallArtifact(clap, .{
            .dest_sub_path = name,
        });
        self.object.step.owner.getInstallStep().dependOn(&install.step);

        return clap;
    }
};
