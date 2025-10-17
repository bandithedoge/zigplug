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
    const check = b.step("check", "Check compile errors");

    const lib = b.addLibrary(.{
        .name = "zigplug",
        .root_module = zigplug,
    });

    var docs_src = std.ArrayList(u8).empty;
    try docs_src.appendSlice(b.allocator,
        \\comptime {@import("std").testing.refAllDeclsRecursive(@This());}
        \\
        \\pub const zigplug = @import("zigplug");
        \\
    );
    const docs_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zigplug", .module = zigplug }},
    });

    check.dependOn(&lib.step);

    if (options.clap) {
        const clap_module = b.addModule("clap", .{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/clap/root.zig"),
            .imports = &.{
                .{ .name = "zigplug", .module = zigplug },
                .{ .name = "zigplug_options", .module = options_module },
            },
        });
        clap_module.addImport("clap", clap_module);

        if (b.lazyDependency("clap", .{})) |clap_dep| {
            const clap_c = b.addTranslateC(.{
                .root_source_file = clap_dep.path("include/clap/clap.h"),
                .target = target,
                .optimize = optimize,
            });
            clap_module.addAnonymousImport("clap_c", .{
                .root_source_file = clap_c.getOutput(),
            });
        }

        const clap_tests = b.addTest(.{ .root_module = clap_module });
        const run_clap_tests = b.addRunArtifact(clap_tests);
        test_step.dependOn(&run_clap_tests.step);

        const clap_lib = b.addLibrary(.{
            .name = "zigplug_clap",
            .root_module = clap_module,
        });

        check.dependOn(&clap_lib.step);

        docs_module.addImport("clap", clap_module);
        try docs_src.appendSlice(b.allocator,
            \\ pub const clap = @import("clap");
            \\
        );
    }

    docs_module.root_source_file =
        b.addWriteFile("docs.zig", try docs_src.toOwnedSlice(b.allocator))
            .getDirectory()
            .path(b, "docs.zig");

    const docs = b.addLibrary(.{
        .name = "zigplug-docs",
        .root_module = docs_module,
    });

    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&install_docs.step);
}

pub const Options = struct {
    /// Doesn't have to match the display name in your plugin's descriptor
    name: []const u8,
    /// Module that contains `plugin()`
    root_module: *std.Build.Module,
    /// Must be the same dependency your plugin imports the "zigplug" module from
    zigplug_dep: *std.Build.Dependency,
    /// Whether to add the resulting compile step to your project's top level install step
    install: bool = true,
};

/// If `options.install` is true, the result will be installed to `lib/clap/{options.name}.clap`
pub fn addClap(b: *std.Build, options: Options) !*std.Build.Step.Compile {
    const entry = b.addWriteFile("entry.zig",
        \\ export const clap_entry = @import("clap").clapEntry(@import("plugin_root"));
    );

    const lib = b.addLibrary(.{
        .name = try std.fmt.allocPrint(b.allocator, "{s}_clap", .{options.name}),
        .linkage = .dynamic,
        // printing to stdout/stderr segfaults without this, possibly a bug in zig's new x86 backend
        .use_llvm = true,
        .root_module = b.createModule(.{
            .target = options.root_module.resolved_target,
            .optimize = options.root_module.optimize,
            .root_source_file = entry.getDirectory().path(b, "entry.zig"),
            .imports = &.{
                .{ .name = "plugin_root", .module = options.root_module },
                .{ .name = "clap", .module = options.zigplug_dep.module("clap") },
            },
        }),
    });

    lib.step.dependOn(&entry.step);

    if (options.install) {
        const install = b.addInstallArtifact(lib, .{
            .dest_sub_path = b.fmt("clap/{s}.clap", .{options.name}),
        });

        b.getInstallStep().dependOn(&install.step);
    }

    return lib;
}
