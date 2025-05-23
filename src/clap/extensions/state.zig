const std = @import("std");
const c = @import("clap_c");
const clap = @import("clap_adapter");
const zigplug = @import("zigplug");

const log = std.log.scoped(.zigplug_clap_state);

pub fn extension(comptime Plugin: type) *const c.clap_plugin_state {
    const state = struct {
        pub fn save(clap_plugin: [*c]const c.clap_plugin, stream: [*c]const c.clap_ostream) callconv(.c) bool {
            const data = clap.Data.cast(clap_plugin);

            for (std.meta.fields(Plugin.desc.Parameters.?), 0..) |_, i| {
                const Param = zigplug.fieldInfoByIndex(Plugin.desc.Parameters.?, i).type;
                const param = zigplug.fieldByIndex(Plugin.desc.Parameters.?, data.parameters.?, i);

                const value = param.get();
                log.debug("saving parameter '{s}' = {!s}", .{ Param.name, Param.format(data.plugin_data.plugin.allocator, value) });

                const size = @sizeOf(Param.Type);

                switch (stream.*.write.?(stream, &value, size)) {
                    size => continue,
                    -1 => {
                        log.err("failed to save parameter '{s}'", .{Param.name});
                        return false;
                    },
                    else => |bytes_written| {
                        log.err(
                            "wrong number of bytes written for parameter '{s}': expected {}, got {}",
                            .{ Param.name, size, bytes_written },
                        );
                        return false;
                    },
                }
            }

            return true;
        }

        pub fn load(clap_plugin: [*c]const c.clap_plugin, stream: [*c]const c.clap_istream) callconv(.c) bool {
            const data = clap.Data.cast(clap_plugin);

            for (std.meta.fields(Plugin.desc.Parameters.?), 0..) |_, i| {
                const Param = zigplug.fieldInfoByIndex(Plugin.desc.Parameters.?, i).type;
                const param = zigplug.fieldByIndex(Plugin.desc.Parameters.?, data.parameters.?, i);

                log.debug("reading parameter {s}", .{Param.name});

                const buffer = data.plugin_data.plugin.allocator.create(Param.Type) catch |e| {
                    log.err("failed to allocate memory for parameter '{s}': {}", .{ Param.name, e });
                    return false;
                };
                defer data.plugin_data.plugin.allocator.destroy(buffer);

                const size = @sizeOf(Param.Type);

                switch (stream.*.read.?(stream, buffer, size)) {
                    size => param.set(buffer.*),
                    -1 => {
                        log.err("failed to read parameter '{s}'", .{Param.name});
                        return false;
                    },
                    else => |bytes_read| {
                        log.err(
                            "wrong number of bytes read for parameter '{s}': expected {}, got {}",
                            .{ Param.name, size, bytes_read },
                        );
                        return false;
                    },
                }
            }
            return false;
        }
    };

    return &.{
        .save = state.save,
        .load = state.load,
    };
}
