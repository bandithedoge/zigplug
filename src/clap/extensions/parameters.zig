const std = @import("std");
const zigplug = @import("../../zigplug.zig");
const clap = @import("../c.zig");
const parameters = @import("../../parameters.zig");

pub fn Parameters(comptime plugin: zigplug.Plugin) type {
    return extern struct {
        pub fn count(clap_plugin: [*c]const clap.clap_plugin_t) callconv(.C) u32 {
            _ = clap_plugin; // autofix

            plugin.data.parameters = std.ArrayList(parameters.Parameter).init(plugin.allocator);

            return @typeInfo(plugin.Parameters).@"enum".fields.len;
        }

        pub fn get_info(clap_plugin: [*c]const clap.clap_plugin_t, index: u32, info: [*c]clap.clap_param_info_t) callconv(.C) bool {
            _ = clap_plugin; // autofix

            if (index >= @typeInfo(plugin.Parameters).@"enum".fields.len)
                return false;

            const param = plugin.callbacks.setupParameter(plugin.Parameters, index);

            info.*.id = index;
            info.*.min_value = param.min.toFloat();
            info.*.max_value = param.max.toFloat();
            info.*.default_value = param.default.toFloat();

            info.*.flags = switch (param.value) {
                .uint, .int, .bool => clap.CLAP_PARAM_IS_STEPPED,
                else => 0,
            };

            std.mem.copyBackwards(u8, &info.*.name, param.name);

            plugin.data.parameters.insert(index, param) catch {
                unreachable;
            };

            return true;
        }

        pub fn get_value(clap_plugin: [*c]const clap.clap_plugin_t, id: clap.clap_id, value: [*c]f64) callconv(.C) bool {
            _ = clap_plugin; // autofix

            if (id >= @typeInfo(plugin.Parameters).@"enum".fields.len)
                return false;

            value.* = plugin.data.parameters.items[id].value.toFloat();

            return true;
        }

        pub fn value_to_text(clap_plugin: [*c]const clap.clap_plugin_t, id: clap.clap_id, value: f64, display: [*c]u8, size: u32) callconv(.C) bool {
            _ = size; // autofix
            _ = display; // autofix
            _ = value; // autofix
            _ = id; // autofix
            _ = clap_plugin; // autofix

            return true;
        }

        pub fn text_to_value(clap_plugin: [*c]const clap.clap_plugin_t, id: clap.clap_id, display: [*c]const u8, value: [*c]f64) callconv(.C) bool {
            _ = value; // autofix
            _ = display; // autofix
            _ = id; // autofix
            _ = clap_plugin; // autofix

            return true;
        }

        pub fn flush(clap_plugin: [*c]const clap.clap_plugin_t, in: [*c]const clap.clap_input_events_t, out: [*c]const clap.clap_output_events_t) callconv(.C) void {
            _ = out; // autofix
            _ = in; // autofix
            _ = clap_plugin; // autofix
        }
    };
}
