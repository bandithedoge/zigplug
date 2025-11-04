const std = @import("std");
const c = @import("clap_c");

pub fn extension(comptime Plugin: type) *const c.clap_plugin_note_ports_t {
    const meta_ports = Plugin.meta.note_ports.?;

    comptime for (meta_ports.in ++ meta_ports.out) |port| {
        if (port.name.len > c.CLAP_NAME_SIZE)
            @compileError(std.fmt.comptimePrint(
                "Note port name too long (max {}): '{s}'",
                .{ c.CLAP_NAME_SIZE, port.name },
            ));
    };

    const note_ports = struct {
        pub fn count(_: [*c]const c.clap_plugin_t, is_input: bool) callconv(.c) u32 {
            const ports = if (is_input) meta_ports.?.in else meta_ports.?.out;
            return @intCast(ports.len);
        }

        pub fn get(_: [*c]const c.clap_plugin_t, index: u32, is_input: bool, info: [*c]c.clap_note_port_info_t) callconv(.c) bool {
            const ports = if (is_input) meta_ports.?.in else meta_ports.?.out;

            if (index >= ports.len) {
                return false;
            }

            const port = ports[index];
            info.*.id = index;
            info.*.supported_dialects = c.CLAP_NOTE_DIALECT_CLAP;
            info.*.preferred_dialect = c.CLAP_NOTE_DIALECT_CLAP;
            std.mem.copyBackwards(u8, &info.*.name, port.name);

            return true;
        }
    };

    return &.{
        .count = note_ports.count,
        .get = note_ports.get,
    };
}
