//! https://github.com/free-audio/clap/blob/main/include/clap/ext/params.h

const c = @import("clap_c");
const clap = @import("clap");

const std = @import("std");

const log = std.log.scoped(.zigplug_clap_parameters);

pub fn extension(comptime Plugin: type) *const c.clap_plugin_params_t {
    std.debug.assert(@hasDecl(Plugin, "Parameters"));
    const parameters = struct {
        pub fn count(_: [*c]const c.clap_plugin_t) callconv(.c) u32 {
            return std.meta.fields(Plugin.Parameters).len;
        }

        pub fn get_info(clap_plugin: [*c]const c.clap_plugin_t, index: u32, info: [*c]c.clap_param_info_t) callconv(.c) bool {
            if (index > std.meta.fields(Plugin.Parameters).len)
                return false;

            const data = clap.Data.fromClap(clap_plugin);
            const param = data.parameters.?[index].*;

            switch (param) {
                inline else => |p| {
                    info.?.* = .{
                        .id = index,
                        .default_value = @TypeOf(p).toFloat(p.options.default),
                        .min_value = @TypeOf(p).toFloat(p.options.min),
                        .max_value = @TypeOf(p).toFloat(p.options.max),
                        .flags = 0,
                    };

                    if (p.options.automatable)
                        info.?.*.flags |= c.CLAP_PARAM_IS_AUTOMATABLE;

                    if (p.options.stepped)
                        info.?.*.flags |= c.CLAP_PARAM_IS_STEPPED;

                    if (p.options.special) |special|
                        switch (special) {
                            .bypass => info.?.*.flags |= c.CLAP_PARAM_IS_BYPASS,
                        };

                    std.mem.copyForwards(u8, &info.?.*.name, p.options.name);
                },
            }

            return true;
        }

        pub fn get_value(clap_plugin: [*c]const c.clap_plugin_t, id: c.clap_id, out: [*c]f64) callconv(.c) bool {
            if (id >= std.meta.fields(Plugin.Parameters).len)
                return false;

            const data = clap.Data.fromClap(clap_plugin);
            const param = data.parameters.?[id].*;
            out.?.* = switch (param) {
                inline else => |p| @TypeOf(p).toFloat(p.get()),
            };

            return true;
        }

        pub fn value_to_text(clap_plugin: [*c]const c.clap_plugin_t, id: c.clap_id, value: f64, out: [*c]u8, out_capacity: u32) callconv(.c) bool {
            if (id >= std.meta.fields(Plugin.Parameters).len)
                return false;

            const data = clap.Data.fromClap(clap_plugin);
            const param = data.parameters.?[id].*;

            const formatted = switch (param) {
                inline else => |p| p.format(data.plugin_data.plugin.allocator, @TypeOf(p).fromFloat(value)),
            } catch {
                log.err("failed to format parameter '{s}': {}", .{ switch (param) {
                    inline else => |p| p.options.name,
                }, value });
                return false;
            };

            defer data.plugin_data.plugin.allocator.free(formatted);

            const size = @min(formatted.len, out_capacity);

            @memcpy(out[0..size], formatted[0..size]);

            // output is not guaranteed to be zeroed out initially, some hosts (reaper) seem to ignore a null terminator
            @memset(out[size..out_capacity], 0);

            return true;
        }

        pub fn text_to_value(clap_plugin: [*c]const c.clap_plugin_t, id: c.clap_id, value_text: [*c]const u8, out: [*c]f64) callconv(.c) bool {
            if (id >= std.meta.fields(Plugin.Parameters).len)
                return false;

            const data = clap.Data.fromClap(clap_plugin);

            const param = data.parameters.?[id].*;
            const text = std.mem.span(value_text);

            out.?.* = switch (param) {
                inline else => |p| @TypeOf(p).toFloat(p.parse(text) catch {
                    log.err("failed to parse parameter '{s}': {s}", .{ p.options.name, value_text });
                    return false;
                }),
            };

            return true;
        }

        pub fn flush(clap_plugin: [*c]const c.clap_plugin_t, in: [*c]const c.clap_input_events_t, _: [*c]const c.clap_output_events_t) callconv(.c) void {
            for (0..in.?.*.size.?(in)) |i| {
                const event = in.?.*.get.?(in, @intCast(i)).?;
                clap.processEvent(Plugin, clap_plugin, event);
            }
        }
    };

    return &.{
        .count = parameters.count,
        .get_info = parameters.get_info,
        .get_value = parameters.get_value,
        .value_to_text = parameters.value_to_text,
        .text_to_value = parameters.text_to_value,
        .flush = parameters.flush,
    };
}
