const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options = .{
        .clap = b.option(bool, "clap", "Build CLAP target") orelse false,
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

    const test_step = b.step("test", "Run unit tests");
    const tests = b.addTest(.{
        .root_module = zigplug,
    });
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);

    const docs_step = b.step("docs", "Build documentation");
    const lib = b.addStaticLibrary(.{
        .name = "zigplug",
        .root_module = zigplug,
    });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&install_docs.step);

    if (options.clap) {
        const clap_adapter = b.addModule("clap_adapter", .{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/clap/adapter.zig"),
            .imports = &.{
                .{ .name = "zigplug", .module = zigplug },
                .{ .name = "zigplug_options", .module = options_module },
            },
        });
        clap_adapter.addImport("clap_adapter", clap_adapter);

        if (b.lazyDependency("clap", .{})) |clap_dep| {
            const clap_c = b.addTranslateC(.{
                .root_source_file = clap_dep.path("include/clap/clap.h"),
                .target = target,
                .optimize = optimize,
            });
            clap_adapter.addAnonymousImport("clap_c", .{
                .root_source_file = clap_c.getOutput(),
            });
        }

        const clap_tests = b.addTest(.{ .root_module = clap_adapter });
        const run_clap_tests = b.addRunArtifact(clap_tests);
        test_step.dependOn(&run_clap_tests.step);
    }
}

// TODO: rethink entire build system
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
            \\ export const clap_entry = @import("clap_adapter").clapEntry(@import("plugin_root"));
        );
        entry.step.dependOn(&self.object.step);

        const clap = b.addSharedLibrary(.{
            .name = name,
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
