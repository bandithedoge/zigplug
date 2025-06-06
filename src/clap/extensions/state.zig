// TODO: use some sort of actual binary serialization
// libs to consider:
// - https://github.com/ziglibs/s2s
// - https://github.com/SeanTheGleaming/zig-serialization
// - https://codeberg.org/hDS9HQLN/ztsl

const std = @import("std");
const c = @import("clap_c");
const clap = @import("clap_adapter");
const zigplug = @import("zigplug");

const log = std.log.scoped(.zigplug_clap_state);

pub fn extension(comptime Plugin: type) *const c.clap_plugin_state {
    _ = Plugin; // autofix
    const state = struct {
        pub fn save(clap_plugin: [*c]const c.clap_plugin, stream: [*c]const c.clap_ostream) callconv(.c) bool {
            const data = clap.Data.cast(clap_plugin);

            for (data.parameters.?) |parameter| {
                switch (parameter) {
                    inline else => |p| {
                        const value = p.get();
                        const bytes = std.mem.toBytes(value);
                        const written = stream.?.*.write.?(stream, &bytes, bytes.len);
                        if (written == -1) {
                            log.err("failed to save parameter '{s}' = {}", .{ p.options.name, value });
                            return false;
                        }

                        log.debug("saved parameter '{s}' = {any}", .{ p.options.name, value });
                    },
                }
            }

            return true;
        }

        pub fn load(clap_plugin: [*c]const c.clap_plugin, stream: [*c]const c.clap_istream) callconv(.c) bool {
            const data = clap.Data.cast(clap_plugin);

            for (data.parameters.?) |*parameter| switch (parameter.*) {
                inline else => |*p| {
                    var value = p.get();
                    const read = stream.?.*.read.?(stream, &value, @sizeOf(@TypeOf(value)));
                    if (read == -1) {
                        log.err("failed to load parameter '{s}'", .{p.options.name});
                        return false;
                    }
                    p.set(value);

                    log.debug("loaded parameter '{s}' = {any}", .{ p.options.name, value });
                },
            };

            return false;
        }
    };

    return &.{
        .save = state.save,
        .load = state.load,
    };
}
