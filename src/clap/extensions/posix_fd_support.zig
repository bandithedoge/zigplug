const zigplug = @import("zigplug");
const clap = @import("c");

pub fn PosixFdSupport(comptime plugin: zigplug.Plugin) type {
    return extern struct {
        pub fn on_fd(clap_plugin: [*c]const clap.clap_plugin_t, fd: c_int, flags: clap.clap_posix_fd_flags_t) callconv(.C) void {
            _ = flags; // autofix
            _ = fd; // autofix
            _ = clap_plugin; // autofix

            if (comptime plugin.gui) |gui| {
                gui.backend.tick(plugin, .Idle) catch {};
            }
        }
    };
}
