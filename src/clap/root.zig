const std = @import("std");

const zigplug = @import("zigplug");
pub const c = @import("clap_c");

pub const log = std.log.scoped(.zigplug_clap);

pub const Feature = @import("features.zig").Feature;

pub const Meta = struct {
    id: [:0]const u8,
    // TODO: custom namespaced features
    features: []const Feature,

    /// This field allows you to extend zigplug's CLAP implementation with extra extensions or override already
    /// supported ones.
    ///
    /// Your function should return a pointer to the extension's struct if the ID matches, and null otherwise.
    ///
    /// See `c` for data types and extension IDs. Use `pluginFromClap` to access your plugin's state from
    /// `c.clap_plugin_t` pointers.
    getExtension: ?*const fn (id: [:0]const u8) ?*const anyopaque = null,
};

/// Get a pointer to our plugin struct from the CLAP plugin state. This is intended to be used in `Meta.getExtension`.
pub fn pluginFromClap(clap_plugin: [*c]const c.clap_plugin_t, comptime T: type) *T {
    const data = Data.fromClap(clap_plugin);
    return @ptrCast(@alignCast(data.plugin_data.plugin.context));
}

pub const Data = struct {
    plugin_data: zigplug.PluginData,
    meta: Meta,

    process_block: zigplug.ProcessBlock,
    parameters: ?[]*zigplug.Parameter = null,

    events: ?struct {
        i: u32 = 0,
        size: u32,
        clap: [*c]const c.clap_input_events_t,
        start: u32,
        end: u32,
    } = null,

    host: [*c]const c.clap_host_t = null,
    host_timer_support: [*c]const c.clap_host_timer_support_t = null,
    host_gui: [*c]const c.clap_host_gui_t = null,

    pub inline fn fromClap(ptr: [*c]const c.clap_plugin_t) *Data {
        return @ptrCast(@alignCast(ptr.*.plugin_data));
    }

    pub fn nextNoteEvent(self: *Data) ?zigplug.NoteEvent {
        const events = &self.events.?;
        while (true) {
            if (events.i >= events.size)
                return null;

            const event = events.clap.*.get.?(events.clap, events.i);

            if (event.*.time >= events.end) return null;
            if (event.*.time < events.start) {
                @branchHint(.cold);
                return null;
            }

            events.i += 1;
            switch (event.*.type) {
                c.CLAP_EVENT_NOTE_ON...c.CLAP_EVENT_NOTE_END => {
                    const note_event: *const c.clap_event_note_t = @ptrCast(@alignCast(event));
                    return .{
                        .type = switch (event.*.type) {
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

    pub fn process(self: *Data, comptime Plugin: type, clap_process: [*c]const c.clap_process, start: u32, end: u32) !void {
        const ports = Plugin.meta.audio_ports.?;
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
                channel_buffers[chan] = input.data32[chan][start..end];

            input_buffers[i] = &channel_buffers;
        }

        var output_buffers: [outputs][][]f32 = undefined;
        inline for (0..outputs) |i| {
            const output = clap_process.*.audio_outputs[i];
            const channels = ports.out[i].channels;

            std.debug.assert(output.channel_count == channels);

            var channel_buffers: [channels][]f32 = undefined;

            inline for (0..channels) |chan|
                channel_buffers[chan] = output.data32[chan][start..end];

            output_buffers[i] = &channel_buffers;
        }

        self.process_block.in = &input_buffers;
        self.process_block.out = &output_buffers;
        self.process_block.samples = end - start;

        self.events = .{
            .clap = clap_process.*.in_events,
            .size = clap_process.*.in_events.*.size.?(clap_process.*.in_events),
            .start = start,
            .end = end,
        };

        try self.plugin_data.plugin.process(self.process_block, self.plugin_data.plugin.parameters);
    }
};

pub fn processEvent(comptime Plugin: type, clap_plugin: *const c.clap_plugin_t, event: *const c.clap_event_header_t) void {
    const data = Data.fromClap(clap_plugin);
    switch (event.type) {
        c.CLAP_EVENT_PARAM_VALUE => {
            std.debug.assert(@hasDecl(Plugin, "Parameters"));
            std.debug.assert(data.parameters != null);

            const value_event: *const c.clap_event_param_value = @ptrCast(@alignCast(event));
            const param = data.parameters.?[value_event.param_id];

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
            if (@hasDecl(Plugin, "Parameters")) {
                const Parameters = Plugin.Parameters;
                const data = Data.fromClap(clap_plugin);
                const allocator = data.plugin_data.plugin.allocator;

                const parameters = allocator.create(Parameters) catch {
                    log.err("Failed to allocate parameters", .{});
                    return false;
                };
                parameters.* = .{};
                const fields = @typeInfo(Parameters).@"struct".fields;

                var parameters_array = allocator.alloc(*zigplug.Parameter, fields.len) catch {
                    log.err("Failed to allocate parameters", .{});
                    return false;
                };

                inline for (fields, 0..) |field, i| {
                    if (field.type != zigplug.Parameter)
                        @compileError("Parameter '" ++ field.name ++ "' is not of type 'zigplug.Parameter'");
                    if (field.default_value_ptr == null)
                        @compileError("Parameter '" ++ field.name ++ "' has no default value");

                    parameters_array[i] = &@field(parameters, field.name);
                }

                data.parameters = parameters_array;
                data.plugin_data.plugin.parameters = parameters;
            }

            return true;
        }

        fn destroy(clap_plugin: [*c]const c.clap_plugin) callconv(.c) void {
            log.debug("destroy()", .{});

            const data = Data.fromClap(clap_plugin);
            const allocator = data.plugin_data.plugin.allocator;

            if (@hasDecl(Plugin, "Parameters")) {
                const Parameters = Plugin.Parameters;
                allocator.free(data.parameters.?);
                const ptr: *Parameters = @ptrCast(@alignCast(data.plugin_data.plugin.parameters));
                allocator.destroy(ptr);
            }

            data.plugin_data.plugin.deinit(Plugin);
            std.heap.page_allocator.destroy(data);
            std.heap.page_allocator.destroy(@as(*const c.clap_plugin, clap_plugin));
        }

        fn activate(clap_plugin: [*c]const c.clap_plugin, sample_rate: f64, min_size: u32, max_size: u32) callconv(.c) bool {
            log.debug("activate({}, {}, {})", .{ sample_rate, min_size, max_size });

            const data = Data.fromClap(clap_plugin);

            data.plugin_data.sample_rate = @intFromFloat(sample_rate);
            data.process_block.sample_rate = data.plugin_data.sample_rate;

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
            const data = Data.fromClap(clap_plugin);

            const samples = clap_process.*.frames_count;

            var start: u32 = 0;
            var end: u32 = samples;

            const event_count = clap_process.*.in_events.*.size.?(clap_process.*.in_events);

            var event_i: u32 = 0;

            while (event_i < event_count) {
                const event = clap_process.*.in_events.*.get.?(clap_process.*.in_events, event_i);
                event_i += 1;
                switch (event.*.type) {
                    c.CLAP_EVENT_PARAM_VALUE => {
                        const value_event: *const c.clap_event_param_value = @ptrCast(@alignCast(event));
                        const param = data.parameters.?[value_event.param_id];

                        if (comptime Plugin.meta.sample_accurate_automation) {
                            end = value_event.header.time;

                            data.process(Plugin, clap_process, start, end) catch |e| {
                                log.err("error while processing: {}", .{e});
                                return c.CLAP_PROCESS_ERROR;
                            };

                            start = end;
                            end = samples;
                        }

                        switch (param.*) {
                            inline else => |*p| {
                                const value = @TypeOf(p.*).fromFloat(value_event.value);
                                p.set(value);
                                zigplug.log.debug("parameter '{s}' = {any} at {}", .{ p.options.name, value, value_event.header.time });
                            },
                        }
                    },
                    else => continue,
                }
            }

            data.process(Plugin, clap_process, start, end) catch |e| {
                log.err("error while processing: {}", .{e});
                return c.CLAP_PROCESS_ERROR;
            };

            return c.CLAP_PROCESS_CONTINUE;
        }

        fn get_extension(clap_plugin: [*c]const c.clap_plugin, id: [*c]const u8) callconv(.c) ?*const anyopaque {
            log.debug("get_extension({s})", .{id});
            const id_slice = std.mem.span(id);

            const data = Data.fromClap(clap_plugin);
            if (data.meta.getExtension) |getExtension|
                if (getExtension(id_slice)) |ptr|
                    return ptr;
            return @import("extensions.zig").getExtension(Plugin, id_slice);
        }

        fn on_main_thread(_: [*c]const c.clap_plugin) callconv(.c) void {
            log.debug("on_main_thread()", .{});
        }
    };
}

fn makeClapDescriptor(comptime Plugin: type) std.mem.Allocator.Error!*const c.clap_plugin_descriptor {
    const meta: zigplug.Meta = Plugin.meta;
    const clap_meta: Meta = Plugin.clap_meta;

    const desc = try std.heap.page_allocator.create(c.clap_plugin_descriptor_t);
    desc.* = .{
        .clap_version = .{
            .major = c.CLAP_VERSION_MAJOR,
            .minor = c.CLAP_VERSION_MINOR,
            .revision = c.CLAP_VERSION_REVISION,
        },

        .id = clap_meta.id,
        .name = meta.name,
        .vendor = meta.vendor,
        .url = meta.url,
        .manual_url = meta.manual_url orelse meta.url,
        .support_url = meta.support_url orelse meta.url,
        .version = meta.version,
        .description = meta.description,
        .features = &[_][*c]const u8{null},
        // TODO: actually implement features
        // .features = blk: {
        //     var features: [clap_meta.features.len + 1:null]?[*:0]const u8 = undefined;
        //     inline for (clap_meta.features, 0..) |feature, i|
        //         features[i] = feature.toString();
        //     // features[clap_meta.features.len] = null;
        //     break :blk &features;
        // },
    };

    return desc;
}

fn PluginFactory(comptime Plugin: type) type {
    return extern struct {
        fn get_plugin_count(_: [*c]const c.clap_plugin_factory) callconv(.c) u32 {
            log.debug("get_plugin_count()", .{});
            return 1;
        }

        fn get_plugin_descriptor(_: [*c]const c.clap_plugin_factory, index: u32) callconv(.c) [*c]const c.clap_plugin_descriptor_t {
            log.debug("get_plugin_descriptor({})", .{index});

            return makeClapDescriptor(Plugin) catch {
                log.err("failed to allocate descriptor", .{});
                return null;
            };
        }

        fn create_plugin(_: [*c]const c.clap_plugin_factory, host: [*c]const c.clap_host_t, plugin_id: [*c]const u8) callconv(.c) [*c]const c.clap_plugin_t {
            log.debug("create_plugin({s})", .{plugin_id});

            const clap_plugin = ClapPlugin(Plugin);

            const plugin = zigplug.Plugin.new(Plugin) catch |e| {
                log.err("failed to initialize plugin: {}", .{e});
                return null;
            };

            std.debug.assert(host != null);

            const plugin_class = std.heap.page_allocator.create(c.clap_plugin_t) catch {
                log.err("Plugin allocation failed", .{});
                return null;
            };

            const plugin_data = std.heap.page_allocator.create(Data) catch {
                log.err("Plugin allocation failed", .{});
                return null;
            };

            plugin_data.* = .{
                .plugin_data = .{
                    .plugin = plugin,
                },
                .meta = Plugin.clap_meta,
                .host = host,
                .process_block = .{
                    .context = plugin_data,
                    .fn_nextNoteEvent = @ptrCast(&Data.nextNoteEvent),
                },
            };

            plugin_class.* = .{
                .desc = makeClapDescriptor(Plugin) catch {
                    log.err("failed to allocate descriptor", .{});
                    return null;
                },
                .plugin_data = plugin_data,
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
    if (!@hasDecl(Plugin, "clap_meta") or @TypeOf(Plugin.clap_meta) != Meta)
        @compileError(
            \\CLAP plugin is missing a metadata object.
            \\
            \\Add one to your root plugin struct:
            \\`pub const clap_meta = @import("zigplug_clap").Meta{...};`
        );

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
    std.testing.refAllDecls(@This());
}
