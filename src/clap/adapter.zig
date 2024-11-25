const std = @import("std");

const zigplug = @import("zigplug");
const options = @import("zigplug_options");
const clap = @import("c");
const features = @import("features.zig");

const Data = struct {
    host: [*c]const clap.clap_host_t,
    host_timer_support: [*c]const clap.clap_host_timer_support_t = null,
    timer_id: clap.clap_id = undefined,

    pub fn cast(ptr: [*c]const clap.clap_plugin_t) *Data {
        return @ptrCast(@alignCast(ptr.*.plugin_data));
    }
};

pub var data: Data = undefined;

fn ClapPlugin(comptime plugin: zigplug.Plugin) type {
    const has_gui = options.with_gui and plugin.gui != null;
    return extern struct {
        fn init(clap_plugin: [*c]const clap.clap_plugin) callconv(.C) bool {
            _ = clap_plugin; // autofix
            zigplug.log.debug("init()\n", .{});

            if (has_gui)
                data.host_timer_support = @ptrCast(@alignCast(data.host.*.get_extension.?(data.host, &clap.CLAP_EXT_TIMER_SUPPORT)));

            const interval = if (comptime plugin.gui) |gui| (if (gui.targetFps) |target| 1000.0 / target) else 200.0;

            if (data.host_timer_support) |host_timer_support| {
                if (host_timer_support.*.register_timer) |register_timer| {
                    return register_timer(data.host, @round(interval), &data.timer_id);
                }
            }

            return true;
        }

        fn destroy(clap_plugin: [*c]const clap.clap_plugin) callconv(.C) void {
            zigplug.log.debug("destroy()\n", .{});

            _ = clap_plugin; // autofix
        }

        fn activate(clap_plugin: [*c]const clap.clap_plugin, sample_rate: f64, min_size: u32, max_size: u32) callconv(.C) bool {
            zigplug.log.debug("activate({}, {}, {})\n", .{ sample_rate, min_size, max_size });

            _ = clap_plugin;
            plugin.data.sample_rate = @intFromFloat(sample_rate);

            return true;
        }

        fn deactivate(clap_plugin: [*c]const clap.clap_plugin) callconv(.C) void {
            zigplug.log.debug("deactivate()\n", .{});

            _ = clap_plugin;
        }

        fn start_processing(clap_plugin: [*c]const clap.clap_plugin) callconv(.C) bool {
            zigplug.log.debug("start_processing()\n", .{});

            _ = clap_plugin;
            return true;
        }

        fn stop_processing(clap_plugin: [*c]const clap.clap_plugin) callconv(.C) void {
            zigplug.log.debug("stop_processing()\n", .{});

            _ = clap_plugin;
        }

        fn reset(clap_plugin: [*c]const clap.clap_plugin) callconv(.C) void {
            zigplug.log.debug("reset()\n", .{});

            _ = clap_plugin;
        }

        fn process(clap_plugin: [*c]const clap.clap_plugin, clap_process: [*c]const clap.clap_process_t) callconv(.C) clap.clap_process_status {
            _ = clap_plugin;

            const samples = clap_process.*.frames_count;

            // process events
            const event_count = clap_process.*.in_events.*.size.?(clap_process.*.in_events);
            var event_index: u32 = 0;
            var next_event_frame = if (event_count > 0) 0 else samples;
            {
                var i: usize = 0;
                while (i < samples) : (i = next_event_frame) {
                    while ((event_index < event_count) and (next_event_frame == i)) {
                        const event = clap_process.*.in_events.*.get.?(clap_process.*.in_events, event_index);

                        if (event.*.time != i) {
                            next_event_frame = event.*.time;
                            break;
                        }

                        @import("events.zig").processEvent(&plugin, event);
                        event_index += 1;

                        if (event_index == event_count) {
                            next_event_frame = samples;
                            break;
                        }
                    }
                }
            }

            // render audio
            const inputs = plugin.ports.in.len;
            const outputs = plugin.ports.out.len;

            std.debug.assert(clap_process.*.audio_inputs_count == inputs);
            std.debug.assert(clap_process.*.audio_outputs_count == outputs);

            var input_buffers: [inputs]zigplug.ProcessBuffer = undefined;
            inline for (0..inputs) |i| {
                const input = clap_process.*.audio_inputs[i];
                const channels = plugin.ports.in[i].channels;

                std.debug.assert(input.channel_count == channels);

                const sample_data: [*][*]f32 = @ptrCast(input.data32);

                input_buffers[i] = .{
                    .data = sample_data[0..channels],
                    .samples = samples,
                };
            }

            var output_buffers: [outputs]zigplug.ProcessBuffer = undefined;
            inline for (0..outputs) |i| {
                const output = clap_process.*.audio_outputs[i];
                const channels = plugin.ports.in[i].channels;

                std.debug.assert(output.channel_count == channels);

                const sample_data: [*][*]f32 = @ptrCast(output.data32);

                output_buffers[i] = .{
                    .data = sample_data[0..channels],
                    .samples = samples,
                };
            }

            const block: zigplug.ProcessBlock = .{
                .in = &input_buffers,
                .out = &output_buffers,
            };

            // FIXME: race condition
            // sometimes this function gets called before all parameters are initialized causing an index out of bounds error
            const status = plugin.callbacks.process(plugin, block);

            if (comptime plugin.gui) |gui| {
                if (comptime gui.sample_access) {
                    if (plugin.data.gui) |*gui_data| {
                        if (gui_data.sample_lock.tryLock()) {
                            defer gui_data.sample_lock.unlock();
                            gui_data.sample_data = block;
                        }
                    }
                }
            }

            // TODO: synchronize main and audio threads

            return switch (status) {
                .ok => clap.CLAP_PROCESS_CONTINUE,
                .failed => clap.CLAP_PROCESS_ERROR,
            };
        }

        fn get_extension(clap_plugin: [*c]const clap.clap_plugin, id: [*c]const u8) callconv(.C) ?*const anyopaque {
            zigplug.log.debug("get_extension({s})\n", .{id});

            _ = clap_plugin;

            return @import("extensions.zig").getExtension(plugin, std.mem.span(id));
        }

        fn on_main_thread(clap_plugin: [*c]const clap.clap_plugin) callconv(.C) void {
            zigplug.log.debug("on_main_thread()\n", .{});

            _ = clap_plugin;
        }
    };
}

fn PluginFactory(comptime plugin: zigplug.Plugin) type {
    return extern struct {
        fn get_plugin_count(factory: [*c]const clap.clap_plugin_factory) callconv(.C) u32 {
            zigplug.log.debug("get_plugin_count()\n", .{});

            _ = factory;
            return 1;
        }

        fn get_plugin_descriptor(factory: [*c]const clap.clap_plugin_factory, index: u32) callconv(.C) [*c]const clap.clap_plugin_descriptor_t {
            zigplug.log.debug("get_plugin_descriptor({any})\n", .{index});

            _ = factory;

            // const feats = features.parseFeatures(plugin.features);
            // const descriptor = makeDescriptor(plugin);
            return &.{
                .clap_version = .{
                    .major = clap.CLAP_VERSION_MAJOR,
                    .minor = clap.CLAP_VERSION_MINOR,
                    .revision = clap.CLAP_VERSION_REVISION,
                },

                .id = plugin.id,
                .name = plugin.name,
                .vendor = plugin.vendor,
                .url = plugin.url,
                .manual_url = plugin.manual_url orelse plugin.url,
                .support_url = plugin.support_url orelse plugin.url,
                .version = plugin.version,
                .description = plugin.description,
                // BUG: using a function causes segfaults
                .features = &[_][*c]const u8{
                    null,
                },
            };
        }

        fn create_plugin(factory: [*c]const clap.clap_plugin_factory, host: [*c]const clap.clap_host_t, plugin_id: [*c]const u8) callconv(.C) [*c]const clap.clap_plugin_t {
            zigplug.log.debug("create_plugin({s})\n", .{plugin_id});
            _ = factory;

            const clap_plugin = ClapPlugin(plugin);
            data.host = host;

            return &.{
                .plugin_data = null,

                .init = clap_plugin.init,
                .destroy = clap_plugin.destroy,
                .activate = clap_plugin.activate,
                .deactivate = clap_plugin.deactivate,
                .start_processing = clap_plugin.start_processing,
                .stop_processing = clap_plugin.stop_processing,
                .reset = clap_plugin.reset,
                .process = clap_plugin.process,
                .get_extension = clap_plugin.get_extension,
                .on_main_thread = clap_plugin.on_main_thread,
            };
        }
    };
}

fn PluginEntry(factory: clap.clap_plugin_factory_t) type {
    return extern struct {
        fn init(plugin_path: [*c]const u8) callconv(.C) bool {
            zigplug.log.debug("init({s})\n", .{plugin_path});

            return true;
        }

        fn deinit() callconv(.C) void {
            zigplug.log.debug("deinit()\n", .{});
        }

        fn get_factory(factory_id: [*c]const u8) callconv(.C) ?*const anyopaque {
            zigplug.log.debug("get_factory({s})\n", .{factory_id});

            const id = std.mem.span(factory_id);

            if (std.mem.eql(u8, id, &clap.CLAP_PLUGIN_FACTORY_ID)) {
                return &factory;
            }

            return null;
        }
    };
}

pub fn clap_entry(comptime plugin: zigplug.Plugin) clap.clap_plugin_entry_t {
    const factory = PluginFactory(plugin);

    const factory_c: clap.clap_plugin_factory_t = .{
        .get_plugin_count = factory.get_plugin_count,
        .get_plugin_descriptor = factory.get_plugin_descriptor,
        .create_plugin = factory.create_plugin,
    };

    const entry = PluginEntry(factory_c);

    return .{
        .clap_version = .{
            .major = clap.CLAP_VERSION_MAJOR,
            .minor = clap.CLAP_VERSION_MINOR,
            .revision = clap.CLAP_VERSION_REVISION,
        },

        .init = entry.init,
        .deinit = entry.deinit,
        .get_factory = entry.get_factory,
    };
}
