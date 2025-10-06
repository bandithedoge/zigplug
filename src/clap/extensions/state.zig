// TODO: use some sort of actual binary serialization
// libs to consider:
// - https://github.com/ziglibs/s2s
// - https://github.com/SeanTheGleaming/zig-serialization
// - https://codeberg.org/hDS9HQLN/ztsl

const c = @import("clap_c");
const clap = @import("clap");

const std = @import("std");
const log = std.log.scoped(.zigplug_clap_state);

pub fn extension(comptime _: type) *const c.clap_plugin_state {
    const state = struct {
        pub fn save(clap_plugin: [*c]const c.clap_plugin, stream: [*c]const c.clap_ostream) callconv(.c) bool {
            const data = clap.Data.fromClap(clap_plugin);

            for (data.parameters.?) |parameter| {
                switch (parameter.*) {
                    inline else => |p| {
                        const value = p.get();
                        const size = @sizeOf(@TypeOf(value));
                        var buffer = std.mem.toBytes(&value);
                        const bytes = stream.*.write.?(stream, @ptrCast(&buffer), size);
                        if (bytes != size) {
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
            const data = clap.Data.fromClap(clap_plugin);

            for (data.parameters.?) |parameter| switch (parameter.*) {
                inline else => |*p| {
                    var value = p.get();
                    const size = @sizeOf(@TypeOf(value));
                    var buffer = std.mem.asBytes(&value);
                    const bytes = stream.*.read.?(stream, @ptrCast(&buffer), size);
                    if (bytes != size) {
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
