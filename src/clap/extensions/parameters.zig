//! https://github.com/free-audio/clap/blob/main/include/clap/ext/params.h

const c = @import("clap_c");
const clap = @import("clap");

const std = @import("std");

pub fn makeParameters(comptime Plugin: type) *const c.clap_plugin_params_t {
    std.debug.assert(@hasDecl(Plugin, "Parameters"));
    const UserParameters = Plugin.Parameters;

    comptime for (std.meta.fields(UserParameters)) |field| {
        const name = switch (field.defaultValue().?) {
            inline else => |p| p.options.name,
        };
        if (name.len > c.CLAP_NAME_SIZE)
            @compileError(std.fmt.comptimePrint("Parameter name too long (max {}): '{s}'", .{ c.CLAP_NAME_SIZE, name }));
    };

    const parameters = struct {
        pub fn count(_: [*c]const c.clap_plugin_t) callconv(.c) u32 {
            return std.meta.fields(UserParameters).len;
        }

        pub fn get_info(clap_plugin: [*c]const c.clap_plugin_t, index: u32, info: [*c]c.clap_param_info_t) callconv(.c) bool {
            if (index > std.meta.fields(UserParameters).len)
                return false;

            const state = clap.State.fromClap(clap_plugin);
            const param = state.plugin.parameters.?.slice[index];

            switch (param.*) {
                inline else => |*p| {
                    info.?.* = .{
                        .id = index,
                        .default_value = @TypeOf(p.*).toFloat(p.options.default),
                        .min_value = @TypeOf(p.*).toFloat(p.options.min),
                        .max_value = @TypeOf(p.*).toFloat(p.options.max),
                        .flags = 0,
                        .cookie = p,
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
            if (id >= std.meta.fields(UserParameters).len)
                return false;

            const state = clap.State.fromClap(clap_plugin);
            const param = state.plugin.parameters.?.slice[id].*;
            out.?.* = switch (param) {
                inline else => |p| @TypeOf(p).toFloat(p.get()),
            };

            return true;
        }

        pub fn value_to_text(clap_plugin: [*c]const c.clap_plugin_t, id: c.clap_id, value: f64, out: [*c]u8, out_capacity: u32) callconv(.c) bool {
            if (id >= std.meta.fields(UserParameters).len)
                return false;

            const state = clap.State.fromClap(clap_plugin);
            const param = state.plugin.parameters.?.slice[id].*;

            const allocator = state.plugin.allocator;
            var buffer = std.Io.Writer.Allocating.init(allocator);
            defer buffer.deinit();
            const writer = &buffer.writer;

            switch (param) {
                inline else => |p| p.format(writer, @TypeOf(p).fromFloat(value)) catch |e| {
                    state.plugin.log.err("failed to format parameter '{s}' ({}): {}", .{ p.options.id.?, value, e });
                    return false;
                },
            }

            const formatted = buffer.toOwnedSlice() catch return false;
            defer allocator.free(formatted);
            if (formatted.len > out_capacity) {
                state.plugin.log.err("parameter value too long: {s}", .{formatted});
                return false;
            }

            const size = @min(formatted.len, out_capacity);

            @memcpy(out[0..size], formatted[0..size]);

            // output is not guaranteed to be zeroed out initially, some hosts (reaper) seem to ignore a null terminator
            @memset(out[size..out_capacity], 0);

            return true;
        }

        pub fn text_to_value(clap_plugin: [*c]const c.clap_plugin_t, id: c.clap_id, value_text: [*c]const u8, out: [*c]f64) callconv(.c) bool {
            if (id >= std.meta.fields(UserParameters).len)
                return false;

            const state = clap.State.fromClap(clap_plugin);

            const param = state.plugin.parameters.?.slice[id].*;
            const text = std.mem.span(value_text);

            out.?.* = switch (param) {
                inline else => |p| @TypeOf(p).toFloat(p.parse(text) catch |e| {
                    state.plugin.log.err("failed to parse parameter '{s}' ({s}): '{}'", .{ p.options.id.?, value_text, e });
                    return false;
                }),
            };

            return true;
        }

        pub fn flush(clap_plugin: [*c]const c.clap_plugin_t, in: [*c]const c.clap_input_events_t, _: [*c]const c.clap_output_events_t) callconv(.c) void {
            for (0..in.?.*.size.?(in)) |i| {
                const event = in.?.*.get.?(in, @intCast(i)).?;
                clap.State.fromClap(clap_plugin).handleEvent(event);
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
