const std = @import("std");
const this = @This();

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options = .{
        .with_gui = b.option(bool, "with_gui", "Build GUI") orelse false,
        .with_clap = b.option(bool, "with_clap", "Build CLAP target") orelse false,
    };

    const options_step = b.addOptions();
    inline for (std.meta.fields(@TypeOf(options))) |field| {
        options_step.addOption(field.type, field.name, @field(options, field.name));
    }

    const zigplug = b.addModule("zigplug", .{
        .root_source_file = b.path("src/zigplug/zigplug.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigplug_options", .module = options_step.createModule() },
        },
    });

    if (options.with_gui) {
        switch (target.result.os.tag) {
            .linux => {
                const dep = b.lazyDependency("system_sdk", .{}).?;
                switch (target.result.cpu.arch) {
                    .x86_64 => {
                        zigplug.addLibraryPath(dep.path("linux/lib/x86_64-linux-gnu"));
                    },
                    .aarch64 => {
                        zigplug.addLibraryPath(dep.path("linux/lib/aarch64-linux-gnu"));
                    },
                    else => {
                        _ = b.addFail("GUI not supported on target arch");
                    },
                }
                zigplug.linkSystemLibrary("X11", .{});
                zigplug.addIncludePath(dep.path("linux/include"));
            },
            else => {
                _ = b.addFail("GUI not supported on target OS");
            },
        }
    }

    if (options.with_clap) {
        const clap_adapter = b.addModule("clap_adapter", .{
            .root_source_file = b.path("src/clap/adapter.zig"),
            .imports = &.{
                .{ .name = "zigplug", .module = zigplug },
            },
        });

        const clap_c = b.addTranslateC(.{
            .root_source_file = b.lazyDependency("clap_api", .{}).?.path("include/clap/clap.h"),
            .target = target,
            .optimize = optimize,
        });
        clap_adapter.addAnonymousImport("c", .{
            .root_source_file = clap_c.getOutput(),
        });
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
            \\ export const clap_entry = @import("clap_adapter").clap_entry(@import("plugin").plugin);
        );
        entry.step.dependOn(&self.object.step);

        const clap = b.addSharedLibrary(.{
            .name = name,
            .root_source_file = entry.getDirectory().path(b, "clap_entry.zig"),
            .target = self.object.root_module.resolved_target orelse b.standardTargetOptions(.{}),
            .optimize = self.object.root_module.optimize orelse b.standardOptimizeOption(.{}),
        });
        clap.step.dependOn(&entry.step);
        clap.root_module.linkLibrary(self.object);
        clap.root_module.addImport("plugin", &self.object.root_module);

        clap.root_module.addImport("clap_adapter", self.zigplug.module("clap_adapter"));

        const install = b.addInstallArtifact(clap, .{
            .dest_sub_path = name,
        });
        b.getInstallStep().dependOn(&install.step);

        return clap;
    }
};
