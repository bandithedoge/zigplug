const std = @import("std");

const zigplug = @import("zigplug");
const c = @import("clap_c");

pub const log = std.log.scoped(.zigplug_clap);
pub const io = @import("io.zig");

pub const Data = struct {
    plugin_data: zigplug.PluginData,

    process_block: zigplug.ProcessBlock,
    parameters: ?[]zigplug.Parameter = null,

    events: ?struct {
        i: u32,
        size: u32,
        clap: [*c]const c.clap_input_events_t,
    } = null,

    host: [*c]const c.clap_host_t = null,
    host_timer_support: [*c]const c.clap_host_timer_support_t = null,
    host_gui: [*c]const c.clap_host_gui_t = null,

    pub inline fn cast(ptr: [*c]const c.clap_plugin_t) *Data {
        return @ptrCast(@alignCast(ptr.*.plugin_data));
    }

    pub fn nextNoteEvent(self: *Data) ?zigplug.NoteEvent {
        const events = &self.events.?;
        while (true) {
            if (events.i >= events.size)
                return null;
            const e = events.clap.*.get.?(events.clap, events.i);
            events.i += 1;
            switch (e.*.type) {
                c.CLAP_EVENT_NOTE_ON...c.CLAP_EVENT_NOTE_END => {
                    const note_event: *const c.clap_event_note_t = @ptrCast(@alignCast(e));
                    return .{
                        .type = switch (e.*.type) {
                            c.CLAP_EVENT_NOTE_ON => .on,
                            c.CLAP_EVENT_NOTE_OFF => .off,
                            c.CLAP_EVENT_NOTE_CHOKE => .choke,
                            c.CLAP_EVENT_NOTE_END => .end,
                            else => unreachable,
                        },
                        .note = if (note_event.key == -1) null else @intCast(note_event.key),
                        .channel = if (note_event.channel == -1) null else @intCast(note_event.channel),
                        .timing = note_event.header.time,
                        .velocity = note_event.velocity,
                    };
                },
                else => {},
            }
        }
    }
};

pub fn processEvent(comptime Plugin: type, clap_plugin: *const c.clap_plugin_t, event: *const c.clap_event_header_t) void {
    const data = Data.cast(clap_plugin);
    switch (event.type) {
        c.CLAP_EVENT_PARAM_VALUE => {
            std.debug.assert(Plugin.desc.Parameters != null);
            std.debug.assert(data.parameters != null);

            const value_event: *const c.clap_event_param_value = @ptrCast(@alignCast(event));
            const param = &data.parameters.?[value_event.param_id];

            switch (param.*) {
                inline else => |*p| {
                    const value = @TypeOf(p.*).fromFloat(value_event.value);
                    p.set(value);
                    zigplug.log.debug("parameter '{s}' = {any}", .{ p.options.name, value });
                },
            }
        },
        else => {},
    }
}

fn ClapPlugin(comptime Plugin: type) type {
    return extern struct {
        fn init(clap_plugin: [*c]const c.clap_plugin) callconv(.c) bool {
            log.debug("init()", .{});

            // TODO: move parameter initialization to a zigplug function
            if (Plugin.desc.Parameters) |Parameters| {
                const data = Data.cast(clap_plugin);

                const fields = @typeInfo(Parameters).@"enum".fields;
                var parameters = data.plugin_data.plugin.allocator.alloc(zigplug.Parameter, fields.len) catch {
                    log.err("parameter allocation failed", .{});
                    return false;
                };
                inline for (0..fields.len) |i| {
                    parameters[i] = Parameters.setup(@enumFromInt(i));
                }

                data.parameters = parameters;
            }

            return true;
        }

        fn destroy(clap_plugin: [*c]const c.clap_plugin) callconv(.c) void {
            log.debug("destroy()", .{});

            const data = Data.cast(clap_plugin);
            data.plugin_data.plugin.deinit();
        }

        fn activate(clap_plugin: [*c]const c.clap_plugin, sample_rate: f64, min_size: u32, max_size: u32) callconv(.c) bool {
            log.debug("activate({}, {}, {})", .{ sample_rate, min_size, max_size });

            const data = Data.cast(clap_plugin);

            data.plugin_data.sample_rate = @intFromFloat(sample_rate);
            data.process_block.sample_rate = data.plugin_data.sample_rate;
            if (comptime Plugin.desc.note_ports) |note_ports| {
                if (note_ports.in.len != 0) {}
            }

            return true;
        }

        fn deactivate(_: [*c]const c.clap_plugin) callconv(.c) void {
            log.debug("deactivate()", .{});
        }

        fn start_processing(_: [*c]const c.clap_plugin) callconv(.c) bool {
            log.debug("start_processing()", .{});
            return true;
        }

        fn stop_processing(_: [*c]const c.clap_plugin) callconv(.c) void {
            log.debug("stop_processing()", .{});
        }

        fn reset(_: [*c]const c.clap_plugin) callconv(.c) void {
            log.debug("reset()", .{});
        }

        fn process(clap_plugin: [*c]const c.clap_plugin, clap_process: [*c]const c.clap_process_t) callconv(.c) c.clap_process_status {
            const data = Data.cast(clap_plugin);

            const samples = clap_process.*.frames_count;

            const event_count = clap_process.*.in_events.*.size.?(clap_process.*.in_events);
            if (event_count != 0)
                for (0..event_count) |event_i|
                    for (0..samples) |i| {
                        const event = clap_process.*.in_events.*.get.?(clap_process.*.in_events, @intCast(event_i));

                        if (event.*.time != i) break;

                        processEvent(Plugin, clap_plugin, event);
                    };

            // render audio
            if (Plugin.desc.audio_ports) |ports| {
                const inputs = ports.in.len;
                const outputs = ports.out.len;

                std.debug.assert(clap_process.*.audio_inputs_count == inputs);
                std.debug.assert(clap_process.*.audio_outputs_count == outputs);

                var input_buffers: [inputs][][]f32 = undefined;
                inline for (0..inputs) |i| {
                    const input = clap_process.*.audio_inputs[i];
                    const channels = ports.in[i].channels;

                    std.debug.assert(input.channel_count == channels);

                    var channel_buffers: [channels][]f32 = undefined;

                    inline for (0..channels) |chan|
                        channel_buffers[chan] = input.data32[chan][0..samples];

                    input_buffers[i] = &channel_buffers;
                }

                var output_buffers: [outputs][][]f32 = undefined;
                inline for (0..outputs) |i| {
                    const output = clap_process.*.audio_outputs[i];
                    const channels = ports.out[i].channels;

                    std.debug.assert(output.channel_count == channels);

                    var channel_buffers: [channels][]f32 = undefined;

                    inline for (0..channels) |chan|
                        channel_buffers[chan] = output.data32[chan][0..samples];

                    output_buffers[i] = &channel_buffers;
                }

                data.process_block.in = &input_buffers;
                data.process_block.out = &output_buffers;
                data.process_block.samples = clap_process.*.frames_count;
                data.events = .{
                    .clap = clap_process.*.in_events,
                    .i = 0,
                    .size = clap_process.*.in_events.*.size.?(clap_process.*.in_events),
                };

                data.plugin_data.plugin.process(data.process_block) catch
                    return c.CLAP_PROCESS_ERROR;
            }

            return c.CLAP_PROCESS_CONTINUE;
        }

        fn get_extension(_: [*c]const c.clap_plugin, id: [*c]const u8) callconv(.c) ?*const anyopaque {
            log.debug("get_extension({s})", .{id});
            return @import("extensions.zig").getExtension(Plugin, std.mem.span(id));
        }

        fn on_main_thread(_: [*c]const c.clap_plugin) callconv(.c) void {
            log.debug("on_main_thread()", .{});
        }
    };
}

fn PluginFactory(comptime Plugin: type) type {
    return extern struct {
        fn get_plugin_count(_: [*c]const c.clap_plugin_factory) callconv(.c) u32 {
            log.debug("get_plugin_count()", .{});
            return 1;
        }

        fn get_plugin_descriptor(_: [*c]const c.clap_plugin_factory, index: u32) callconv(.c) [*c]const c.clap_plugin_descriptor_t {
            log.debug("get_plugin_descriptor({any})", .{index});

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
                    .major = c.CLAP_VERSION_MAJOR,
                    .minor = c.CLAP_VERSION_MINOR,
                    .revision = c.CLAP_VERSION_REVISION,
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

        fn create_plugin(_: [*c]const c.clap_plugin_factory, host: [*c]const c.clap_host_t, plugin_id: [*c]const u8) callconv(.c) [*c]const c.clap_plugin_t {
            log.debug("create_plugin({s})", .{plugin_id});

            const clap_plugin = ClapPlugin(Plugin);

            const plugin: zigplug.Plugin = Plugin.plugin() catch return null;

            std.debug.assert(host != null);

            const plugin_class = plugin.allocator.create(c.clap_plugin_t) catch {
                log.err("Plugin allocation failed", .{});
                return null;
            };

            plugin_class.*.plugin_data = plugin.allocator.create(Data) catch {
                log.err("Plugin allocation failed", .{});
                return null;
            };

            const plugin_data = Data.cast(plugin_class);
            plugin_data.* = .{
                .plugin_data = .{
                    .plugin = plugin,
                },
                .host = host,
                .process_block = .{
                    .context = plugin_data,
                    .fn_nextNoteEvent = @ptrCast(&Data.nextNoteEvent),
                },
            };

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

fn PluginEntry(factory: c.clap_plugin_factory_t) type {
    return extern struct {
        fn init(plugin_path: [*c]const u8) callconv(.c) bool {
            log.debug("init({s})", .{plugin_path});

            return true;
        }

        fn deinit() callconv(.c) void {
            log.debug("deinit()", .{});
        }

        fn get_factory(factory_id: [*c]const u8) callconv(.c) ?*const anyopaque {
            log.debug("get_factory({s})", .{factory_id});

            const id = std.mem.span(factory_id);

            if (std.mem.eql(u8, id, &c.CLAP_PLUGIN_FACTORY_ID)) {
                return &factory;
            }

            return null;
        }
    };
}

pub fn clapEntry(comptime Plugin: type) c.clap_plugin_entry_t {
    const factory = PluginFactory(Plugin);

    const factory_c: c.clap_plugin_factory_t = .{
        .get_plugin_count = factory.get_plugin_count,
        .get_plugin_descriptor = factory.get_plugin_descriptor,
        .create_plugin = factory.create_plugin,
    };

    const entry = PluginEntry(factory_c);

    return .{
        .clap_version = .{
            .major = c.CLAP_VERSION_MAJOR,
            .minor = c.CLAP_VERSION_MINOR,
            .revision = c.CLAP_VERSION_REVISION,
        },

        .init = entry.init,
        .deinit = entry.deinit,
        .get_factory = entry.get_factory,
    };
}

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
