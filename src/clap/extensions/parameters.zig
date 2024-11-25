const std = @import("std");
const zigplug = @import("zigplug");
const clap = @import("c");

pub fn Parameters(comptime plugin: zigplug.Plugin) type {
    return extern struct {
        pub fn count(clap_plugin: [*c]const clap.clap_plugin_t) callconv(.C) u32 {
            _ = clap_plugin; // autofix

            std.debug.assert(plugin.Parameters != null);
            std.debug.assert(plugin.callbacks.setupParameter != null);

            plugin.data.param_lock.lock();
            defer plugin.data.param_lock.unlock();

            plugin.data.parameters = std.ArrayList(zigplug.parameters.Parameter).init(plugin.allocator);

            return @typeInfo(plugin.Parameters.?).@"enum".fields.len;
        }

        pub fn get_info(clap_plugin: [*c]const clap.clap_plugin_t, index: u32, info: [*c]clap.clap_param_info_t) callconv(.C) bool {
            _ = clap_plugin; // autofix

            if (index >= @typeInfo(plugin.Parameters.?).@"enum".fields.len)
                return false;

            const param = plugin.callbacks.setupParameter.?(plugin.Parameters.?, index);

            info.*.id = index;
            info.*.min_value = param.min.toFloat();
            info.*.max_value = param.max.toFloat();
            info.*.default_value = param.default.toFloat();

            info.*.flags = switch (param.value) {
                .uint, .int, .bool => clap.CLAP_PARAM_IS_STEPPED,
                else => 0,
            };

            std.mem.copyBackwards(u8, &info.*.name, param.name);

            plugin.data.param_lock.lock();
            defer plugin.data.param_lock.unlock();

            plugin.data.parameters.insert(index, param) catch {
                unreachable;
            };

            return true;
        }

        pub fn get_value(clap_plugin: [*c]const clap.clap_plugin_t, id: clap.clap_id, value: [*c]f64) callconv(.C) bool {
            _ = clap_plugin; // autofix

            if (id >= @typeInfo(plugin.Parameters.?).@"enum".fields.len)
                return false;

            plugin.data.param_lock.lock();
            defer plugin.data.param_lock.unlock();

            value.* = plugin.data.parameters.items[id].value.toFloat();

            return true;
        }

        pub fn value_to_text(clap_plugin: [*c]const clap.clap_plugin_t, id: clap.clap_id, value: f64, display: [*c]u8, size: u32) callconv(.C) bool {
            _ = clap_plugin; // autofix

            var param = plugin.data.parameters.items[id];
            param.value.fromFloat(value);

            const result = param.value.print(plugin.allocator) catch {
                zigplug.log.err("formatting parameter value failed: {}", .{value});
                return false;
            };

            std.mem.copyBackwards(
                u8,
                display[0..size],
                if (param.unit) |unit|
                    std.fmt.allocPrintZ(plugin.allocator, "{s} {s}", .{ result, unit }) catch {
                        return false;
                    }
                else
                    result,
            );

            return true;
        }

        pub fn text_to_value(clap_plugin: [*c]const clap.clap_plugin_t, id: clap.clap_id, display: [*c]const u8, value: [*c]f64) callconv(.C) bool {
            _ = clap_plugin; // autofix

            var param = plugin.data.parameters.items[id];
            const src = std.mem.span(display);

            param.value = (switch (param.value) {
                .float => .{ .float = std.fmt.parseFloat(f32, src) catch {
                    return false;
                } },
                .int => .{ .int = std.fmt.parseInt(i32, src, 10) catch {
                    return false;
                } },
                .uint => .{ .uint = std.fmt.parseUnsigned(u32, src, 10) catch {
                    return false;
                } },
                .bool => .{ .bool = std.mem.eql(u8, src, "true") },
            });

            value.* = param.value.toFloat();

            return true;
        }

        pub fn flush(clap_plugin: [*c]const clap.clap_plugin_t, in: [*c]const clap.clap_input_events_t, out: [*c]const clap.clap_output_events_t) callconv(.C) void {
            _ = out; // autofix
            _ = in; // autofix
            _ = clap_plugin; // autofix
        }
    };
}
