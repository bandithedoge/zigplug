const std = @import("std");

const zigplug = @import("zigplug");
const options = @import("zigplug_options");
const clap = @import("clap_c");

const events = @import("events.zig");

pub const Data = struct {
    plugin: zigplug.Plugin,
    host: [*c]const clap.clap_host_t = undefined,

    plugin_data: zigplug.PluginData = undefined,

    host_timer_support: [*c]const clap.clap_host_timer_support_t = null,
    host_gui: [*c]const clap.clap_host_gui_t = null,
    timer_id: clap.clap_id = undefined,

    pub fn cast(ptr: [*c]const clap.clap_plugin_t) *Data {
        return @ptrCast(@alignCast(ptr.*.plugin_data));
    }
};

fn ClapPlugin(comptime Plugin: type) type {
    const has_gui = options.with_gui and Plugin.desc.gui != null;
    const has_params = Plugin.desc.Parameters != null;

    return extern struct {
        fn init(clap_plugin: [*c]const clap.clap_plugin) callconv(.c) bool {
            zigplug.log.debug("init()\n", .{});

            const data = Data.cast(clap_plugin);

            if (has_gui) {
                data.host_timer_support = @ptrCast(@alignCast(data.host.*.get_extension.?(data.host, &clap.CLAP_EXT_TIMER_SUPPORT)));
                data.host_gui = @ptrCast(@alignCast(data.host.*.get_extension.?(data.host, &clap.CLAP_EXT_GUI)));

                const interval = if (comptime Plugin.desc.gui) |gui| (if (gui.targetFps) |target| 1000.0 / target else 200.0) else 200.0;

                if (data.host_timer_support) |host_timer_support| {
                    if (host_timer_support.*.register_timer) |register_timer| {
                        return register_timer(data.host, @round(interval), &data.timer_id);
                    }
                }
            }

            return true;
        }

        fn destroy(clap_plugin: [*c]const clap.clap_plugin) callconv(.c) void {
            zigplug.log.debug("destroy()\n", .{});

            const data = Data.cast(clap_plugin);
            data.plugin.deinit();
            // data.plugin.destroy(Plugin);
            // data.plugin.allocator.destroy(@as(*Data, @ptrCast(@alignCast(clap_plugin.?.*.plugin_data))));
            // data.plugin.allocator.destroy(@as(*const clap.clap_plugin_t, clap_plugin));
        }

        fn activate(clap_plugin: [*c]const clap.clap_plugin, sample_rate: f64, min_size: u32, max_size: u32) callconv(.c) bool {
            zigplug.log.debug("activate({}, {}, {})\n", .{ sample_rate, min_size, max_size });

            const data = Data.cast(clap_plugin);

            data.plugin_data.sample_rate = @intFromFloat(sample_rate);

            return true;
        }

        fn deactivate(clap_plugin: [*c]const clap.clap_plugin) callconv(.c) void {
            zigplug.log.debug("deactivate()\n", .{});

            _ = clap_plugin;
        }

        fn start_processing(clap_plugin: [*c]const clap.clap_plugin) callconv(.c) bool {
            zigplug.log.debug("start_processing()\n", .{});

            _ = clap_plugin;
            return true;
        }

        fn stop_processing(clap_plugin: [*c]const clap.clap_plugin) callconv(.c) void {
            zigplug.log.debug("stop_processing()\n", .{});

            _ = clap_plugin;
        }

        fn reset(clap_plugin: [*c]const clap.clap_plugin) callconv(.c) void {
            zigplug.log.debug("reset()\n", .{});

            _ = clap_plugin;
        }

        fn process(clap_plugin: [*c]const clap.clap_plugin, clap_process: [*c]const clap.clap_process_t) callconv(.c) clap.clap_process_status {
            const data = Data.cast(clap_plugin);

            if (has_params)
                events.syncMainToAudio(Plugin, data, clap_process.*.out_events);

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

                        events.processEvent(Plugin, clap_plugin, event);
                        event_index += 1;

                        if (event_index == event_count) {
                            next_event_frame = samples;
                            break;
                        }
                    }
                }
            }

            // render audio
            const inputs = Plugin.desc.ports.in.len;
            const outputs = Plugin.desc.ports.out.len;

            std.debug.assert(clap_process.*.audio_inputs_count == inputs);
            std.debug.assert(clap_process.*.audio_outputs_count == outputs);

            var input_buffers: [inputs]zigplug.ProcessBuffer = undefined;
            inline for (0..inputs) |i| {
                const input = clap_process.*.audio_inputs[i];
                const channels = Plugin.desc.ports.in[i].channels;

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
                const channels = Plugin.desc.ports.in[i].channels;

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
                .sample_rate = data.plugin_data.sample_rate,
            };

            // FIXME: race condition
            // sometimes this function gets called before all parameters are initialized causing an index out of bounds error
            const status = data.plugin.process(block);

            if (comptime Plugin.desc.gui) |gui| {
                if (comptime gui.sample_access) {
                    if (data.plugin_data.gui) |*gui_data| {
                        if (gui_data.sample_lock.tryLock()) {
                            defer gui_data.sample_lock.unlock();
                            gui_data.sample_data = block;
                        }
                    }
                }
            }

            return switch (status) {
                .ok => clap.CLAP_PROCESS_CONTINUE,
                .failed => clap.CLAP_PROCESS_ERROR,
            };
        }

        fn get_extension(clap_plugin: [*c]const clap.clap_plugin, id: [*c]const u8) callconv(.c) ?*const anyopaque {
            zigplug.log.debug("get_extension({s})\n", .{id});
            _ = clap_plugin; // autofix

            return @import("extensions.zig").getExtension(Plugin, std.mem.span(id));
        }

        fn on_main_thread(clap_plugin: [*c]const clap.clap_plugin) callconv(.c) void {
            zigplug.log.debug("on_main_thread()\n", .{});

            _ = clap_plugin;
        }
    };
}

fn PluginFactory(comptime Plugin: type) type {
    return extern struct {
        fn get_plugin_count(factory: [*c]const clap.clap_plugin_factory) callconv(.c) u32 {
            zigplug.log.debug("get_plugin_count()\n", .{});

            _ = factory;
            return 1;
        }

        fn get_plugin_descriptor(factory: [*c]const clap.clap_plugin_factory, index: u32) callconv(.c) [*c]const clap.clap_plugin_descriptor_t {
            zigplug.log.debug("get_plugin_descriptor({any})\n", .{index});

            _ = factory;

            // const FeatureMap = std.EnumMap(zigplug.Feature, [*c]const u8);
            //
            // const map = FeatureMap.init(.{
            //     .instrument = clap.CLAP_PLUGIN_FEATURE_INSTRUMENT,
            //     .effect = clap.CLAP_PLUGIN_FEATURE_AUDIO_EFFECT,
            //     .note_effect = clap.CLAP_PLUGIN_FEATURE_NOTE_EFFECT,
            //     .note_detector = clap.CLAP_PLUGIN_FEATURE_NOTE_DETECTOR,
            //     .analyzer = clap.CLAP_PLUGIN_FEATURE_ANALYZER,
            //     .synthesizer = clap.CLAP_PLUGIN_FEATURE_SYNTHESIZER,
            //     .sampler = clap.CLAP_PLUGIN_FEATURE_SAMPLER,
            //     .drum = clap.CLAP_PLUGIN_FEATURE_DRUM,
            //     .drum_machine = clap.CLAP_PLUGIN_FEATURE_DRUM_MACHINE,
            //     .filter = clap.CLAP_PLUGIN_FEATURE_FILTER,
            //     .phaser = clap.CLAP_PLUGIN_FEATURE_PHASER,
            //     .equalizer = clap.CLAP_PLUGIN_FEATURE_EQUALIZER,
            //     .deesser = clap.CLAP_PLUGIN_FEATURE_DEESSER,
            //     .phase_vocoder = clap.CLAP_PLUGIN_FEATURE_PHASE_VOCODER,
            //     .granular = clap.CLAP_PLUGIN_FEATURE_GRANULAR,
            //     .frequency_shifter = clap.CLAP_PLUGIN_FEATURE_FREQUENCY_SHIFTER,
            //     .pitch_shifter = clap.CLAP_PLUGIN_FEATURE_PITCH_SHIFTER,
            //     .distortion = clap.CLAP_PLUGIN_FEATURE_DISTORTION,
            //     .transient_shaper = clap.CLAP_PLUGIN_FEATURE_TRANSIENT_SHAPER,
            //     .compressor = clap.CLAP_PLUGIN_FEATURE_COMPRESSOR,
            //     .expander = clap.CLAP_PLUGIN_FEATURE_EXPANDER,
            //     .gate = clap.CLAP_PLUGIN_FEATURE_GATE,
            //     .limiter = clap.CLAP_PLUGIN_FEATURE_LIMITER,
            //     .flanger = clap.CLAP_PLUGIN_FEATURE_FLANGER,
            //     .chorus = clap.CLAP_PLUGIN_FEATURE_CHORUS,
            //     .delay = clap.CLAP_PLUGIN_FEATURE_DELAY,
            //     .reverb = clap.CLAP_PLUGIN_FEATURE_REVERB,
            //     .tremolo = clap.CLAP_PLUGIN_FEATURE_TREMOLO,
            //     .glitch = clap.CLAP_PLUGIN_FEATURE_GLITCH,
            //     .utility = clap.CLAP_PLUGIN_FEATURE_UTILITY,
            //     .pitch_correction = clap.CLAP_PLUGIN_FEATURE_PITCH_CORRECTION,
            //     .restoration = clap.CLAP_PLUGIN_FEATURE_RESTORATION,
            //     .multi_effects = clap.CLAP_PLUGIN_FEATURE_MULTI_EFFECTS,
            //     .mixing = clap.CLAP_PLUGIN_FEATURE_MIXING,
            //     .mastering = clap.CLAP_PLUGIN_FEATURE_MASTERING,
            //     .mono = clap.CLAP_PLUGIN_FEATURE_MONO,
            //     .stereo = clap.CLAP_PLUGIN_FEATURE_STEREO,
            //     .surround = clap.CLAP_PLUGIN_FEATURE_SURROUND,
            //     .ambisonic = clap.CLAP_PLUGIN_FEATURE_AMBISONIC,
            // });
            //
            // var features = std.BoundedArray([*c]const u8, @typeInfo(zigplug.Feature).@"enum".fields.len).init(plugin.features.len) catch return null;
            // for (plugin.features) |feature| {
            //     features.appendAssumeCapacity(map.getAssertContains(feature));
            // }
            // features.appendAssumeCapacity(null);

            return &.{
                .clap_version = .{
                    .major = clap.CLAP_VERSION_MAJOR,
                    .minor = clap.CLAP_VERSION_MINOR,
                    .revision = clap.CLAP_VERSION_REVISION,
                },

                .id = Plugin.desc.id,
                .name = Plugin.desc.name,
                .vendor = Plugin.desc.vendor,
                .url = Plugin.desc.url,
                .manual_url = Plugin.desc.manual_url orelse Plugin.desc.url,
                .support_url = Plugin.desc.support_url orelse Plugin.desc.url,
                .version = Plugin.desc.version,
                .description = Plugin.desc.description,
                // FIXME: segfault
                // .features = features.constSlice().ptr,
                .features = &[_][*c]const u8{null},
            };
        }

        fn create_plugin(factory: [*c]const clap.clap_plugin_factory, host: [*c]const clap.clap_host_t, plugin_id: [*c]const u8) callconv(.c) [*c]const clap.clap_plugin_t {
            zigplug.log.debug("create_plugin({s})\n", .{plugin_id});
            _ = factory;

            const clap_plugin = ClapPlugin(Plugin);

            // var plugin: Plugin = Plugin.init();
            const plugin: zigplug.Plugin = Plugin.plugin();
            // const desc = plugin.callbacks.descriptor();

            std.debug.assert(host != null);

            const plugin_class = plugin.allocator.create(clap.clap_plugin_t) catch {
                zigplug.log.err("Plugin allocation failed", .{});
                return null;
            };

            plugin_class.*.plugin_data = plugin.allocator.create(Data) catch {
                zigplug.log.err("Plugin allocation failed (OOM)", .{});
                return null;
            };

            const plugin_data = Data.cast(plugin_class);
            plugin_data.plugin = plugin;
            plugin_data.host = host;

            plugin_class.*.init = clap_plugin.init;
            plugin_class.*.destroy = clap_plugin.destroy;
            plugin_class.*.activate = clap_plugin.activate;
            plugin_class.*.deactivate = clap_plugin.deactivate;
            plugin_class.*.start_processing = clap_plugin.start_processing;
            plugin_class.*.stop_processing = clap_plugin.stop_processing;
            plugin_class.*.reset = clap_plugin.reset;
            plugin_class.*.process = clap_plugin.process;
            plugin_class.*.get_extension = clap_plugin.get_extension;
            plugin_class.*.on_main_thread = clap_plugin.on_main_thread;

            return plugin_class;
        }
    };
}

fn PluginEntry(factory: clap.clap_plugin_factory_t) type {
    return extern struct {
        fn init(plugin_path: [*c]const u8) callconv(.c) bool {
            zigplug.log.debug("init({s})\n", .{plugin_path});

            return true;
        }

        fn deinit() callconv(.c) void {
            zigplug.log.debug("deinit()\n", .{});
        }

        fn get_factory(factory_id: [*c]const u8) callconv(.c) ?*const anyopaque {
            zigplug.log.debug("get_factory({s})\n", .{factory_id});

            const id = std.mem.span(factory_id);

            if (std.mem.eql(u8, id, &clap.CLAP_PLUGIN_FACTORY_ID)) {
                return &factory;
            }

            return null;
        }
    };
}

pub fn clap_entry(comptime plugin: type) clap.clap_plugin_entry_t {
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
