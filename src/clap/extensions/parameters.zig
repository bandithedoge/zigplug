const std = @import("std");
const zigplug = @import("zigplug");
const clap = @import("clap_adapter");
const c = @import("clap_c");

const events = @import("../events.zig");

pub fn Parameters(comptime Plugin: type) *const c.clap_plugin_params_t {
    const parameters = struct {
        pub fn count(clap_plugin: [*c]const c.clap_plugin_t) callconv(.C) u32 {
            const data = clap.Data.cast(clap_plugin);

            std.debug.assert(Plugin.desc.Parameters != null);
            std.debug.assert(@typeInfo(Plugin.desc.Parameters.?) == .Enum);

            data.plugin_data.param_lock.lock();
            defer data.plugin_data.param_lock.unlock();

            data.plugin_data.parameters = std.ArrayList(zigplug.parameters.Parameter).init(Plugin.desc.allocator);

            return @typeInfo(Plugin.desc.Parameters.?).Enum.fields.len;
        }

        pub fn get_info(clap_plugin: [*c]const c.clap_plugin_t, index: u32, info: [*c]c.clap_param_info_t) callconv(.C) bool {
            const data = clap.Data.cast(clap_plugin);

            if (index >= @typeInfo(Plugin.desc.Parameters.?).Enum.fields.len)
                return false;

            // const param = plugin.callbacks.setupParameter.?(plugin.Parameters.?, index);
            const param = Plugin.desc.Parameters.?.setup(@enumFromInt(index));

            info.*.id = index;
            info.*.min_value = param.min.toFloat();
            info.*.max_value = param.max.toFloat();
            info.*.default_value = param.default.toFloat();

            info.*.flags = switch (param.value) {
                .uint, .int, .bool => c.CLAP_PARAM_IS_STEPPED,
                else => 0,
            };

            std.mem.copyBackwards(u8, &info.*.name, param.name);

            data.plugin_data.param_lock.lock();
            defer data.plugin_data.param_lock.unlock();

            data.plugin_data.parameters.insert(index, param) catch unreachable;

            return true;
        }

        pub fn get_value(clap_plugin: [*c]const c.clap_plugin_t, id: c.clap_id, value: [*c]f64) callconv(.C) bool {
            const data = clap.Data.cast(clap_plugin);

            if (id >= @typeInfo(Plugin.desc.Parameters.?).Enum.fields.len)
                return false;

            data.plugin_data.param_lock.lock();
            defer data.plugin_data.param_lock.unlock();

            const param = &data.plugin_data.parameters.items[id];

            value.* = if (param.main_changed) param.main_value.toFloat() else param.get().toFloat();

            return true;
        }

        pub fn value_to_text(clap_plugin: [*c]const c.clap_plugin_t, id: c.clap_id, value: f64, display: [*c]u8, size: u32) callconv(.C) bool {
            const data = clap.Data.cast(clap_plugin);

            var param = data.plugin_data.parameters.items[id];
            param.value.fromFloat(value);

            const result = param.value.print(Plugin.desc.allocator) catch {
                zigplug.log.err("formatting parameter value failed: {}", .{value});
                return false;
            };

            std.mem.copyBackwards(
                u8,
                display[0..size],
                if (param.unit) |unit|
                    std.fmt.allocPrintZ(Plugin.desc.allocator, "{s} {s}", .{ result, unit }) catch {
                        return false;
                    }
                else
                    result,
            );

            return true;
        }

        pub fn text_to_value(clap_plugin: [*c]const c.clap_plugin_t, id: c.clap_id, display: [*c]const u8, value: [*c]f64) callconv(.C) bool {
            const data = clap.Data.cast(clap_plugin);

            var param = data.plugin_data.parameters.items[id];
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

        pub fn flush(clap_plugin: [*c]const c.clap_plugin_t, in: [*c]const c.clap_input_events_t, out: [*c]const c.clap_output_events_t) callconv(.C) void {
            const data = clap.Data.cast(clap_plugin);

            events.syncMainToAudio(Plugin, data, out);

            for (0..in.*.size.?(in)) |i| {
                events.processEvent(Plugin, clap_plugin, in.*.get.?(in, @intCast(i)));
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
