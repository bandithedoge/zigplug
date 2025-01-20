const std = @import("std");
const zigplug = @import("zigplug");
const options = @import("zigplug_options");
const clap = @import("clap_adapter");
const c = @import("clap_c");

pub fn getExtension(comptime Plugin: type, id: [:0]const u8) ?*const anyopaque {
    if (std.mem.eql(u8, id, &c.CLAP_EXT_AUDIO_PORTS)) {
        return @import("extensions/audio_ports.zig").AudioPorts(Plugin);
    }

    if (comptime Plugin.desc.Parameters != null) {
        if (std.mem.eql(u8, id, &c.CLAP_EXT_PARAMS)) {
            return @import("extensions/parameters.zig").Parameters(Plugin);
        }

        if (std.mem.eql(u8, id, &c.CLAP_EXT_STATE)) {
            return @import("extensions/state.zig").State(Plugin);
        }
    }

    if (Plugin.desc.gui != null and options.with_gui) {
        if (std.mem.eql(u8, id, &c.CLAP_EXT_GUI)) {
            return @import("extensions/gui.zig").Gui(Plugin);
        }

        if (std.mem.eql(u8, id, &c.CLAP_EXT_POSIX_FD_SUPPORT)) {
            return @import("extensions/posix_fd_support.zig").PosixFdSupport(Plugin);
        }

        if (std.mem.eql(u8, id, &c.CLAP_EXT_TIMER_SUPPORT)) {
            return @import("extensions/timer_support.zig").TimerSupport(Plugin);
        }
    }

    return null;
}
