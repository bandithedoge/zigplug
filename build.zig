const std = @import("std");

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

    const zigplug_lib = b.addLibrary(.{
        .name = "zigplug",
        .root_module = zigplug,
    });

    b.installArtifact(zigplug_lib);

    if (options.with_gui) {
        if (b.lazyDependency("pugl", .{
            .target = target,
            .optimize = optimize,
            .xrandr = false,
            .xcursor = false,
            .opengl = options.gui_backend == .gl,
            .cairo = options.gui_backend == .cairo,
            .stub = options.gui_backend == .external,
        })) |pugl| {
            zigplug_lib.installLibraryHeaders(pugl.artifact("pugl"));
            zigplug.addImport("pugl", pugl.module("pugl"));

            switch (options.gui_backend) {
                .gl => zigplug.addImport("backend_opengl", pugl.module("backend_opengl")),
                .cairo => zigplug.addImport("backend_cairo", pugl.module("backend_cairo")),
                else => unreachable,
            }
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
        const name = b.fmt("{s}.clap", .{self.object.name});

        const entry = b.addWriteFile("clap_entry.zig",
            \\ export const clap_entry = @import("clap_adapter").clap_entry(@import("plugin_root"));
        );
        entry.step.dependOn(&self.object.step);

        const clap = b.addLibrary(.{
            .name = name,
            .linkage = .dynamic,
            .root_module = b.createModule(.{
                .root_source_file = entry.getDirectory().path(b, "clap_entry.zig"),
                .target = self.object.root_module.resolved_target orelse b.standardTargetOptions(.{}),
                .optimize = self.object.root_module.optimize orelse b.standardOptimizeOption(.{}),
                .imports = &.{
                    .{ .name = "plugin_root", .module = self.object.root_module },
                    .{ .name = "clap_adapter", .module = self.zigplug.module("clap_adapter") },
                },
            }),
        });
        clap.step.dependOn(&entry.step);

        const install = self.object.step.owner.addInstallArtifact(clap, .{
            .dest_sub_path = name,
        });
        self.object.step.owner.getInstallStep().dependOn(&install.step);

        return clap;
    }
};
