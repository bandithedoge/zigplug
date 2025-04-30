const std = @import("std");
const zigplug = @import("zigplug");
const clap = @import("clap_adapter");
const c = @import("clap_c");

const events = @import("../events.zig");

const log = std.log.scoped(.clapState);

pub fn State(comptime Plugin: type) *const c.clap_plugin_state_t {
    const state = struct {
        pub fn save(clap_plugin: [*c]const c.clap_plugin_t, stream: [*c]const c.clap_ostream_t) callconv(.c) bool {
            log.debug("save()", .{});
            const data = clap.Data.cast(clap_plugin);

            _ = events.syncAudioToMain(Plugin, data);

            const param_count = @typeInfo(Plugin.desc.Parameters.?).@"enum".fields.len;
            var params = data.plugin_data.parameters.clone() catch {
                return false;
            };

            return @sizeOf(zigplug.parameters.Parameter) * param_count == stream.*.write.?(stream, (params.toOwnedSlice() catch {
                return false;
            }).ptr, @sizeOf(zigplug.parameters.Parameter) * param_count);
        }

        pub fn load(clap_plugin: [*c]const c.clap_plugin_t, stream: [*c]const c.clap_istream_t) callconv(.c) bool {
            log.debug("load()", .{});
            const data = clap.Data.cast(clap_plugin);

            data.plugin_data.param_lock.lock();
            defer data.plugin_data.param_lock.unlock();

            const param_count = @typeInfo(Plugin.desc.Parameters.?).@"enum".fields.len;
            var buffer: [param_count]zigplug.parameters.Parameter = undefined;

            const result = @sizeOf(zigplug.parameters.Parameter) * param_count == stream.*.read.?(stream, &buffer, @sizeOf(zigplug.parameters.Parameter) * param_count);

            for (data.plugin_data.parameters.items, 0..) |*param, i| {
                param.set(buffer[i].get());
            }

            return result;
        }
    };

    return &.{
        .save = state.save,
        .load = state.load,
    };
}
