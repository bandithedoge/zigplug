const std = @import("std");
const zigplug = @import("zigplug");
const c = @import("clap_c");

pub fn extension(comptime Plugin: type) *const c.clap_plugin_audio_ports_t {
    const audio_ports = struct {
        pub fn count(clap_plugin: [*c]const c.clap_plugin_t, is_input: bool) callconv(.c) u32 {
            _ = clap_plugin; // autofix

            const ports = if (is_input) Plugin.desc.ports.in else Plugin.desc.ports.out;

            return @intCast(ports.len);
        }

        pub fn get(clap_plugin: [*c]const c.clap_plugin_t, index: u32, is_input: bool, info: [*c]c.clap_audio_port_info_t) callconv(.c) bool {
            _ = clap_plugin; // autofix

            const ports = if (is_input) Plugin.desc.ports.in else Plugin.desc.ports.out;

            if (index >= ports.len) {
                return false;
            }

            const port = ports[index];

            info.*.id = index;
            info.*.channel_count = port.channels;
            info.*.flags = if (index == 0) c.CLAP_AUDIO_PORT_IS_MAIN else 0;
            info.*.port_type = switch (port.channels) {
                1 => &c.CLAP_PORT_MONO,
                2 => &c.CLAP_PORT_STEREO,
                else => null,
            };
            info.*.in_place_pair = c.CLAP_INVALID_ID;
            std.mem.copyBackwards(u8, &info.*.name, port.name);

            return true;
        }
    };

    return &.{
        .count = audio_ports.count,
        .get = audio_ports.get,
    };
}
