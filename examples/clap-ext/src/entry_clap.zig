const std = @import("std");
const clap = @import("zigplug_clap");

const ClapExtExample = @import("ClapExtExample");

// let's implement the "note-name" extension, which is not supported in zigplug (yet?).
// we can test this in reaper for example
//
// https://github.com/free-audio/clap/blob/main/include/clap/ext/note-name.h
fn getExtension(id: [:0]const u8) ?*const anyopaque {
    if (std.mem.eql(u8, id, &clap.c.CLAP_EXT_NOTE_NAME)) {
        const ext = struct {
            pub fn count(_: [*c]const clap.c.clap_plugin_t) callconv(.c) u32 {
                return 1;
            }

            pub fn get(clap_plugin: [*c]const clap.c.clap_plugin_t, index: u32, note_name: [*c]clap.c.clap_note_name_t) callconv(.c) bool {
                // you can use this to access your plugin's state
                const self = clap.pluginFromClap(clap_plugin, ClapExtExample);
                _ = self;

                if (index == 0) {
                    // let's set the name of every note to some string
                    note_name.* = .{
                        // zig initializes c structs with `std.mem.zeroes` so we don't have to deal with an undefined
                        // name value
                        .port = -1,
                        .key = -1,
                        .channel = -1,
                    };
                    std.mem.copyForwards(u8, &note_name.*.name, "Hello world... i mean note");
                    return true;
                }
                return false;
            }
        };
        return &clap.c.clap_plugin_note_name_t{
            .count = ext.count,
            .get = ext.get,
        };
    }
    return null;
}

comptime {
    clap.exportClap(ClapExtExample, .{
        .id = "com.bandithedoge.zigplug_clap_ext_example",
        .features = &.{ .instrument, .synthesizer, .mono },
        .extra_features = &.{"custom-namespace:custom-feature"},
        .getExtension = getExtension,
    });
}
