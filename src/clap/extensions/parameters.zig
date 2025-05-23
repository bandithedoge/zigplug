//! https://github.com/free-audio/clap/blob/main/include/clap/ext/params.h

const c = @import("clap_c");
const clap = @import("clap_adapter");
const zigplug = @import("zigplug");

const std = @import("std");

const log = std.log.scoped(.zigplug_clap_parameters);

pub fn extension(comptime Plugin: type) *const c.clap_plugin_params_t {
    std.debug.assert(Plugin.desc.Parameters != null);
    const parameters = struct {
        pub fn count(clap_plugin: [*c]const c.clap_plugin_t) callconv(.c) u32 {
            _ = clap_plugin; // autofix
            return std.meta.fields(Plugin.desc.Parameters.?).len;
        }

        pub fn getInfo(clap_plugin: [*c]const c.clap_plugin_t, index: u32, info: [*c]c.clap_param_info_t) callconv(.c) bool {
            _ = clap_plugin; // autofix
            const Param = zigplug.fieldInfoByIndex(Plugin.desc.Parameters.?, index).type;

            info.?.* = .{
                .id = index,
                .default_value = Param.toFloat(Param.default),
                .min_value = Param.toFloat(Param.min),
                .max_value = Param.toFloat(Param.max),
            };

            std.mem.copyForwards(u8, &info.?.*.name, Param.name);

            return true;
        }

        pub fn getValue(clap_plugin: [*c]const c.clap_plugin_t, id: c.clap_id, out: [*c]f64) callconv(.c) bool {
            if (id >= std.meta.fields(Plugin.desc.Parameters.?).len)
                return false;

            const data = clap.Data.cast(clap_plugin);
            out.?.* = zigplug.fieldByIndex(Plugin.desc.Parameters.?, data.parameters.?, id).getFloat();

            return true;
        }

        pub fn valueToText(clap_plugin: [*c]const c.clap_plugin_t, id: c.clap_id, value: f64, out: [*c]u8, out_capacity: u32) callconv(.c) bool {
            if (id >= std.meta.fields(Plugin.desc.Parameters.?).len)
                return false;

            const data = clap.Data.cast(clap_plugin);
            const Param = zigplug.fieldInfoByIndex(Plugin.desc.Parameters.?, id).type;

            const formatted = Param.format(data.plugin_data.plugin.allocator, Param.fromFloat(value)) catch {
                log.err("failed to format parameter '{s}': {}", .{ Param.name, value });
                return false;
            };
            defer data.plugin_data.plugin.allocator.free(formatted);

            std.mem.copyForwards(u8, out[0..out_capacity], formatted);

            // output is not guaranteed to be zeroed out initially
            // and some hosts (reaper) seem to ignore a null terminator
            @memset(out[formatted.len..out_capacity], 0);

            return true;
        }

        pub fn textToValue(clap_plugin: [*c]const c.clap_plugin_t, id: c.clap_id, value_text: [*c]const u8, out: [*c]f64) callconv(.c) bool {
            _ = clap_plugin; // autofix
            if (id >= std.meta.fields(Plugin.desc.Parameters.?).len)
                return false;

            const Param = zigplug.fieldInfoByIndex(Plugin.desc.Parameters.?, id).type;

            const value = Param.parse(std.mem.span(value_text)) catch {
                log.err("failed to parse parameter '{s}': {s}", .{ Param.name, value_text });
                return false;
            };
            out.?.* = Param.toFloat(value);

            return true;
        }

        pub fn flush(clap_plugin: [*c]const c.clap_plugin_t, in: [*c]const c.clap_input_events_t, out: [*c]const c.clap_output_events_t) callconv(.c) void {
            _ = out; // don't need to send parameter change events between threads when we have atomics
            for (0..in.?.*.size.?(in)) |i| {
                const event = in.?.*.get.?(in, @intCast(i)).?;
                clap.processEvent(Plugin, clap_plugin, event);
            }
        }
    };

    return &.{
        .count = parameters.count,
        .get_info = parameters.getInfo,
        .get_value = parameters.getValue,
        .value_to_text = parameters.valueToText,
        .text_to_value = parameters.textToValue,
        .flush = parameters.flush,
    };
}
