// TODO: use some sort of actual binary serialization
// libs to consider:
// - https://github.com/ziglibs/s2s
// - https://github.com/SeanTheGleaming/zig-serialization
// - https://codeberg.org/hDS9HQLN/ztsl

const c = @import("clap_c");
const clap = @import("clap_adapter");
const s2s = @import("s2s");

const std = @import("std");
const log = std.log.scoped(.zigplug_clap_state);

pub fn extension(comptime _: type) *const c.clap_plugin_state {
    const state = struct {
        pub fn save(clap_plugin: [*c]const c.clap_plugin, stream: [*c]const c.clap_ostream) callconv(.c) bool {
            const data = clap.Data.cast(clap_plugin);
            const writer = clap.io.writer(stream.?);

            for (data.parameters.?) |parameter| {
                switch (parameter) {
                    inline else => |p| {
                        const value = p.get();
                        const bytes = std.mem.toBytes(value);
                        writer.writeAll(&bytes) catch {
                            log.err("failed to save parameter '{s}' = {}", .{ p.options.name, value });
                            return false;
                        };
                        log.debug("saved parameter '{s}' = {any}", .{ p.options.name, value });
                    },
                }
            }

            return true;
        }

        pub fn load(clap_plugin: [*c]const c.clap_plugin, stream: [*c]const c.clap_istream) callconv(.c) bool {
            const data = clap.Data.cast(clap_plugin);
            const reader = clap.io.reader(stream.?);

            for (data.parameters.?) |*parameter| switch (parameter.*) {
                inline else => |*p| {
                    var value = p.get();
                    _ = reader.readAll(std.mem.asBytes(&value)) catch {
                        log.err("failed to load parameter '{s}'", .{p.options.name});
                        return false;
                    };
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
