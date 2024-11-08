const std = @import("std");
const zigplug = @import("zigplug");
const options = @import("zigplug_options");
const clap = @import("c");

pub fn getExtension(comptime plugin: zigplug.Plugin, id: [:0]const u8) ?*const anyopaque {
    if (std.mem.eql(u8, id, &clap.CLAP_EXT_AUDIO_PORTS)) {
        const audio_ports = @import("extensions/audio_ports.zig").AudioPorts(plugin);
        const ext: clap.clap_plugin_audio_ports_t = .{
            .count = audio_ports.count,
            .get = audio_ports.get,
        };
        return &ext;
    }

    if (std.mem.eql(u8, id, &clap.CLAP_EXT_PARAMS)) {
        const parameters = @import("extensions/parameters.zig").Parameters(plugin);
        const ext: clap.clap_plugin_params_t = .{
            .count = parameters.count,
            .get_info = parameters.get_info,
            .get_value = parameters.get_value,
            .value_to_text = parameters.value_to_text,
            .text_to_value = parameters.text_to_value,
            .flush = parameters.flush,
        };
        return &ext;
    }

    if (std.mem.eql(u8, id, &clap.CLAP_EXT_STATE)) {
        const state = @import("extensions/state.zig").State(plugin);
        const ext: clap.clap_plugin_state_t = .{
            .save = state.save,
            .load = state.load,
        };
        return &ext;
    }

    if (plugin.gui != null and options.with_gui) {
        if (std.mem.eql(u8, id, &clap.CLAP_EXT_GUI)) {
            const gui = @import("extensions/gui.zig").Gui(plugin);
            const ext: clap.clap_plugin_gui_t = .{
                .is_api_supported = gui.is_api_supported,
                .get_preferred_api = gui.get_preferred_api,
                .create = gui.create,
                .destroy = gui.destroy,
                .set_scale = gui.set_scale,
                .get_size = gui.get_size,
                .can_resize = gui.can_resize,
                .get_resize_hints = gui.get_resize_hints,
                .adjust_size = gui.adjust_size,
                .set_size = gui.set_size,
                .set_parent = gui.set_parent,
                .set_transient = gui.set_transient,
                .suggest_title = gui.suggest_title,
                .show = gui.show,
                .hide = gui.hide,
            };
            return &ext;
        }

        if (std.mem.eql(u8, id, &clap.CLAP_EXT_POSIX_FD_SUPPORT)) {
            const posix_fd_support = @import("extensions/posix_fd_support.zig").PosixFdSupport(plugin);
            const ext: clap.clap_plugin_posix_fd_support_t = .{
                .on_fd = posix_fd_support.on_fd,
            };
            return &ext;
        }

        if (std.mem.eql(u8, id, &clap.CLAP_EXT_TIMER_SUPPORT)) {
            const timer_support = @import("extensions/timer_support.zig").TimerSupport(plugin);
            const ext: clap.clap_plugin_timer_support_t = .{
                .on_timer = timer_support.on_timer,
            };
            return &ext;
        }
    }

    return null;
}
