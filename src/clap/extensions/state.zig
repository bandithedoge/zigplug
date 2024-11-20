const std = @import("std");
const zigplug = @import("zigplug");
const clap = @import("c");

pub fn State(comptime plugin: zigplug.Plugin) type {
    return extern struct {
        pub fn save(clap_plugin: [*c]const clap.clap_plugin_t, stream: [*c]const clap.clap_ostream_t) callconv(.C) bool {
            _ = clap_plugin; // autofix

            const param_count = @typeInfo(plugin.Parameters.?).@"enum".fields.len;
            var params = plugin.data.parameters.clone() catch {
                return false;
            };
            return @sizeOf(zigplug.parameters.Parameter) * param_count == stream.*.write.?(stream, (params.toOwnedSlice() catch {
                return false;
            }).ptr, @sizeOf(zigplug.parameters.Parameter) * param_count);
        }

        pub fn load(clap_plugin: [*c]const clap.clap_plugin_t, stream: [*c]const clap.clap_istream_t) callconv(.C) bool {
            _ = clap_plugin; // autofix

            plugin.data.mutex.lock();
            defer plugin.data.mutex.unlock();

            const param_count = @typeInfo(plugin.Parameters.?).@"enum".fields.len;
            var buffer: [param_count]zigplug.parameters.Parameter = undefined;

            const result = @sizeOf(zigplug.parameters.Parameter) * param_count == stream.*.read.?(stream, &buffer, @sizeOf(zigplug.parameters.Parameter) * param_count);

            plugin.data.parameters = std.ArrayList(zigplug.parameters.Parameter).fromOwnedSlice(plugin.allocator, &buffer);

            return result;
        }
    };
}
