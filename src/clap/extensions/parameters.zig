//! https://github.com/free-audio/clap/blob/main/include/clap/ext/params.h

const c = @import("clap_c");
const clap = @import("clap_adapter");
const zigplug = @import("zigplug");

const std = @import("std");

pub fn getExtension(comptime Plugin: type) *const c.clap_plugin_params_t {
    std.debug.assert(Plugin.desc.Parameters != null);
    const parameters = struct {
        pub fn count(clap_plugin: [*c]const c.clap_plugin_t) callconv(.c) u32 {
            _ = clap_plugin; // autofix
            return std.meta.fields(Plugin.desc.Parameters.?).len;
        }

        pub fn getInfo(clap_plugin: [*c]const c.clap_plugin_t, index: u32, info: [*c]c.clap_param_info_t) callconv(.c) bool {
            _ = clap_plugin; // autofix
            const param = zigplug.fieldInfoByIndex(Plugin.desc.Parameters.?, index);

            info.?.* = .{
                .id = index,
                .default_value = param.type.toFloat(param.type.default),
                .min_value = param.type.toFloat(param.type.min),
                .max_value = param.type.toFloat(param.type.max),
            };

            std.mem.copyForwards(u8, &info.?.*.name, param.type.name);

            return true;
        }

        pub fn getValue(clap_plugin: [*c]const c.clap_plugin_t, id: c.clap_id, out: [*c]f64) callconv(.c) bool {
            std.debug.assert(id < std.meta.fields(Plugin.desc.Parameters.?).len);

            const data = clap.Data.cast(clap_plugin);
            out.?.* = zigplug.fieldByIndex(Plugin.desc.Parameters.?, data.parameters.?, id).getFloat();

            return true;
        }

        // TODO
        pub fn valueToText(clap_plugin: [*c]const c.clap_plugin_t, id: c.clap_id, value: f64, out: [*c]u8, out_capacity: u32) callconv(.c) bool {
            _ = out_capacity; // autofix
            _ = out; // autofix
            _ = value; // autofix
            _ = id; // autofix
            _ = clap_plugin; // autofix
            return true;
        }

        // TODO
        pub fn textToValue(clap_plugin: [*c]const c.clap_plugin_t, id: c.clap_id, value_text: [*c]const u8, out: [*c]f64) callconv(.c) bool {
            _ = out; // autofix
            _ = value_text; // autofix
            _ = id; // autofix
            _ = clap_plugin; // autofix
            return true;
        }

        // TODO
        pub fn flush(clap_plugin: [*c]const c.clap_plugin_t, in: [*c]const c.clap_input_events_t, out: [*c]const c.clap_output_events_t) callconv(.c) void {
            _ = out; // autofix
            _ = in; // autofix
            _ = clap_plugin; // autofix
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
