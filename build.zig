const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const clap = b.addSharedLibrary(.{
        .name = "zigplug.clap",
        .root_source_file = b.path("src/test_plugin.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const clap_c = b.dependency("clap", .{});

    clap.addIncludePath(clap_c.path("include"));

    const install = b.addInstallArtifact(clap, .{ .dest_sub_path = "zigplug.clap" });
    b.getInstallStep().dependOn(&install.step);
}
