const std = @import("std");
const zigplug = @import("zigplug");
const c = @import("clap_c");

pub fn makeAudioPorts(comptime Plugin: type) *const c.clap_plugin_audio_ports_t {
    const meta_ports = Plugin.meta.audio_ports.?;

    comptime for (meta_ports.in ++ meta_ports.out) |port| {
        if (port.name.len > c.CLAP_NAME_SIZE)
            @compileError(std.fmt.comptimePrint(
                "Audio port name too long (max {}): '{s}'",
                .{ c.CLAP_NAME_SIZE, port.name },
            ));
    };

    const audio_ports = struct {
        pub fn count(_: [*c]const c.clap_plugin_t, is_input: bool) callconv(.c) u32 {
            return @intCast(if (is_input) meta_ports.in.len else meta_ports.out.len);
        }

        pub fn get(_: [*c]const c.clap_plugin_t, index: u32, is_input: bool, info: [*c]c.clap_audio_port_info_t) callconv(.c) bool {
            const ports = if (is_input) Plugin.meta.audio_ports.?.in else Plugin.meta.audio_ports.?.out;

            if (index >= ports.len) {
                return false;
            }

            const port = ports[index];

            info.* = .{
                .id = index,
                .channel_count = port.channels,
                .flags = if (index == 0) c.CLAP_AUDIO_PORT_IS_MAIN else 0,
                .port_type = switch (port.channels) {
                    1 => &c.CLAP_PORT_MONO,
                    2 => &c.CLAP_PORT_STEREO,
                    else => null,
                },
                .in_place_pair = c.CLAP_INVALID_ID,
            };

            std.mem.copyForwards(u8, &info.*.name, port.name);

            return true;
        }
    };

    return &.{
        .count = audio_ports.count,
        .get = audio_ports.get,
    };
}
