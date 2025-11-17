const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core_dep = b.dependency("core", .{
        .target = target,
        .optimize = optimize,
    });

    try b.modules.put("zigplug", core_dep.module("zigplug"));

    const test_step = b.step("test", "Run unit tests");

    const core_tests = b.addSystemCommand(&.{ "zig", "build", "test" });
    core_tests.setCwd(b.path("src/core"));
    test_step.dependOn(&core_tests.step);

    const clap_tests = b.addSystemCommand(&.{ "zig", "build", "test" });
    clap_tests.setCwd(b.path("src/clap"));
    test_step.dependOn(&clap_tests.step);
}

pub fn clapModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    const dep = b.dependencyFromBuildZig(@This(), .{
        .target = target,
        .optimize = optimize,
    });

    if (dep.builder.lazyDependency("clap", .{
        .target = target,
        .optimize = optimize,
    })) |clap_dep|
        return clap_dep.module("clap");

    unreachable;
}

pub const Options = struct {
    /// Doesn't have to match the display name in your plugin's descriptor
    name: []const u8,
    /// Module that contains `plugin()`
    root_module: *std.Build.Module,
    /// Whether to add the resulting compile step to your project's top level install step
    install: bool = true,
};

/// If `options.install` is true, the result will be installed to `lib/clap/{options.name}.clap`
pub fn addClap(b: *std.Build, options: Options) !*std.Build.Step.Compile {
    const entry = b.addWriteFile("entry.zig",
        \\ export const clap_entry = @import("clap").clapEntry(@import("plugin_root"));
    );

    const target = options.root_module.resolved_target.?;
    const optimize = options.root_module.optimize.?;

    const lib = b.addLibrary(.{
        .name = try std.fmt.allocPrint(b.allocator, "{s}_clap", .{options.name}),
        .linkage = .dynamic,
        // printing to stdout/stderr segfaults without this, possibly a bug in zig's new x86 backend
        .use_llvm = true,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = entry.getDirectory().path(b, "entry.zig"),
            .imports = &.{
                .{ .name = "plugin_root", .module = options.root_module },
                .{ .name = "clap", .module = clapModule(b, target, optimize) },
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
