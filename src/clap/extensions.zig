const std = @import("std");
const zigplug = @import("../zigplug.zig");
const clap = @import("c.zig");

pub fn AudioPorts(comptime plugin: zigplug.Plugin) type {
    return extern struct {
        pub fn count(clap_plugin: [*c]const clap.clap_plugin_t, is_input: bool) callconv(.C) u32 {
            _ = clap_plugin; // autofix

            const ports = if (is_input) plugin.ports.in else plugin.ports.out;

            return @intCast(ports.len);
        }

        pub fn get(clap_plugin: [*c]const clap.clap_plugin_t, index: u32, is_input: bool, info: [*c]clap.clap_audio_port_info_t) callconv(.C) bool {
            _ = clap_plugin; // autofix

            const ports = if (is_input) plugin.ports.in else plugin.ports.out;

            if (index >= ports.len) {
                return false;
            }

            const port = ports[index];

            info.*.id = index;
            info.*.channel_count = port.channels;
            info.*.flags = if (index == 0) clap.CLAP_AUDIO_PORT_IS_MAIN else 0;
            info.*.port_type = switch (port.channels) {
                1 => &clap.CLAP_PORT_MONO,
                2 => &clap.CLAP_PORT_STEREO,
                else => null,
            };
            info.*.in_place_pair = clap.CLAP_INVALID_ID;
            std.mem.copyBackwards(u8, &info.*.name, port.name);

            return true;
        }
    };
}
