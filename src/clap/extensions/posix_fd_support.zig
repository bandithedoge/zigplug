const std = @import("std");
const zigplug = @import("zigplug");
const c = @import("clap_c");

const log = std.log.scoped(.ClapPosixFdSupport);

pub fn PosixFdSupport(comptime Plugin: type) *const c.clap_plugin_posix_fd_support_t {
    const posix_fd_support = struct {
        pub fn on_fd(clap_plugin: [*c]const c.clap_plugin_t, fd: c_int, flags: c.clap_posix_fd_flags_t) callconv(.C) void {
            log.debug("on_fd({}, {})", .{fd, flags});
            _ = clap_plugin; // autofix

            if (comptime Plugin.desc.gui) |gui| {
                gui.backend.tick(Plugin, .Idle) catch {};
            }
        }
    };

    return &.{
        .on_fd = posix_fd_support.on_fd,
    };
}
