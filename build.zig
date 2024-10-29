const std = @import("std");
const this = @This();

pub fn build(b: *std.Build) void {
    _ = b.addModule("zigplug", .{
        .root_source_file = b.path("src/zigplug.zig"),
    });
}

pub const Plugin = struct {
    options: Options,
    b: *std.Build,

    pub const Options = struct {
        name: []const u8,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        source_file: std.Build.LazyPath,
    };

    var zigplug: *std.Build.Dependency = undefined;
    var object: *std.Build.Step.Compile = undefined;

    /// Creates a static library from your plugin source.
    /// The root source file *must* export `pub const plugin: zigplug.Plugin`.
    pub fn new(b: *std.Build, options: Options) Plugin {
        zigplug = b.dependencyFromBuildZig(this, .{});

        object = b.addStaticLibrary(.{
            .name = "plugin",
            .target = options.target,
            .optimize = options.optimize,
            .root_source_file = options.source_file,
        });

        object.root_module.addImport("zigplug", zigplug.module("zigplug"));

        return .{
            .options = options,
            .b = b,
        };
    }

    pub fn addClapTarget(self: *const Plugin) !*std.Build.Step.Compile {
        const name = try std.mem.concat(self.b.allocator, u8, &[_][]const u8{ self.options.name, ".clap" });

        const entry = self.b.addWriteFile("clap_entry.zig",
            \\ export const clap_entry = @import("clap_adapter").clap_entry(@import("plugin").plugin);
        );
        entry.step.dependOn(&object.step);

        const clap = self.b.addSharedLibrary(.{
            .name = name,
            .root_source_file = entry.getDirectory().path(self.b, "clap_entry.zig"),
            .target = self.options.target,
            .optimize = self.options.optimize,
        });
        clap.step.dependOn(&entry.step);
        clap.root_module.linkLibrary(object);
        clap.root_module.addImport("plugin", &object.root_module);

        const clap_adapter = self.b.addModule("clap_adapter", .{
            .root_source_file = zigplug.builder.path("src/clap/adapter.zig"),
        });
        clap_adapter.addImport("zigplug", zigplug.module("zigplug"));

        const clap_c = zigplug.builder.lazyDependency("clap_api", .{});
        clap_adapter.addIncludePath(clap_c.?.path("include"));

        clap.root_module.addImport("clap_adapter", clap_adapter);

        const install = self.b.addInstallArtifact(clap, .{
            .dest_sub_path = name,
        });
        self.b.getInstallStep().dependOn(&install.step);

        return clap;
    }
};
