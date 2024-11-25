const std = @import("std");
const zigplug = @import("zigplug");
const clap = @import("c");

pub fn TimerSupport(comptime plugin: zigplug.Plugin) type {
    return extern struct {
        pub fn on_timer(clap_plugin: [*c]const clap.clap_plugin_t, id: clap.clap_id) callconv(.C) void {
            _ = id; // autofix
            _ = clap_plugin; // autofix
            if (plugin.data.gui) |gui| {
                if (gui.created)
                    plugin.gui.?.backend.tick(plugin) catch {};
            }
        }
    };
}
