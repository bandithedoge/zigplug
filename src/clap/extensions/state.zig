const std = @import("std");
const zigplug = @import("zigplug");
const clap = @import("c");

const events = @import("../events.zig");

const log = std.log.scoped(.clapState);

pub fn State(comptime plugin: zigplug.Plugin) type {
    return extern struct {
        pub fn save(clap_plugin: [*c]const clap.clap_plugin_t, stream: [*c]const clap.clap_ostream_t) callconv(.C) bool {
            log.debug("save()", .{});
            _ = clap_plugin; // autofix

            _ = events.syncAudioToMain(plugin);

            const param_count = @typeInfo(plugin.Parameters.?).@"enum".fields.len;
            var params = plugin.data.parameters.clone() catch {
                return false;
            };

            if (comptime plugin.gui) |gui| {
                if (plugin.data.gui) |gui_data|
                    if (gui_data.visible)
                        gui.backend.tick(plugin, .StateChanged) catch return false;
            }

            return @sizeOf(zigplug.parameters.Parameter) * param_count == stream.*.write.?(stream, (params.toOwnedSlice() catch {
                return false;
            }).ptr, @sizeOf(zigplug.parameters.Parameter) * param_count);
        }

        pub fn load(clap_plugin: [*c]const clap.clap_plugin_t, stream: [*c]const clap.clap_istream_t) callconv(.C) bool {
            log.debug("load()", .{});
            _ = clap_plugin; // autofix

            plugin.data.param_lock.lock();
            defer plugin.data.param_lock.unlock();

            const param_count = @typeInfo(plugin.Parameters.?).@"enum".fields.len;
            var buffer: [param_count]zigplug.parameters.Parameter = undefined;

            const result = @sizeOf(zigplug.parameters.Parameter) * param_count == stream.*.read.?(stream, &buffer, @sizeOf(zigplug.parameters.Parameter) * param_count);

            for (plugin.data.parameters.items, 0..) |*param, i| {
                param.set(buffer[i].get());
            }

            if (comptime plugin.gui) |gui| {
                if (plugin.data.gui) |gui_data|
                    if (gui_data.visible)
                        gui.backend.tick(plugin, .StateChanged) catch return false;
            }

            return result;
        }
    };
}
