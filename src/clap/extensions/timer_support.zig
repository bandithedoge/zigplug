const std = @import("std");
const zigplug = @import("zigplug");
const clap = @import("clap_adapter");
const c = @import("clap_c");

pub fn TimerSupport(comptime Plugin: type) *const c.clap_plugin_timer_support_t {
    const timer_support = struct {
        pub fn on_timer(clap_plugin: [*c]const c.clap_plugin_t, id: c.clap_id) callconv(.c) void {
            _ = id; // autofix

            const data = clap.Data.cast(clap_plugin);

            if (data.plugin_data.gui) |gui| {
                if (gui.created)
                    Plugin.desc.gui.?.backend.tick(Plugin, .Idle) catch {};
            }
        }
    };

    return &.{
        .on_timer = timer_support.on_timer,
    };
}
