const std = @import("std");

const zigplug = @import("zigplug");
pub const c = @import("clap_c");

pub const Feature = @import("features.zig").Feature;

pub const Meta = struct {
    /// Reverse URI is recommended
    id: [:0]const u8,
    features: []const Feature,
    /// Non-standard features should be formatted as `$namespace:$feature`
    extra_features: ?[]const [:0]const u8 = null,

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
    const state = State.fromClap(clap_plugin);
    return @ptrCast(@alignCast(state.plugin.context));
}

pub fn hostLog(context: *anyopaque, level: std.log.Level, text: [:0]const u8) void {
    const state: *State = @ptrCast(@alignCast(context));
    state.host_log.*.log.?(
        state.host,
        switch (level) {
            .err => c.CLAP_LOG_ERROR,
            .warn => c.CLAP_LOG_WARNING,
            .info => c.CLAP_LOG_INFO,
            .debug => c.CLAP_LOG_DEBUG,
        },
        text,
    );
}

pub const State = struct {
    plugin: zigplug.Plugin,
    meta: Meta,

    process_block: zigplug.ProcessBlock,

    events: ?struct {
        i: u32 = 0,
        size: u32,
        clap: [*c]const c.clap_input_events_t,
        start: u32,
        end: u32,
    } = null,

    host: [*c]const c.clap_host_t = null,
    host_log: [*c]const c.clap_host_log_t = null,
    host_timer_support: [*c]const c.clap_host_timer_support_t = null,
    host_gui: [*c]const c.clap_host_gui_t = null,

    pub inline fn fromClap(ptr: [*c]const c.clap_plugin_t) *State {
        return @ptrCast(@alignCast(ptr.*.plugin_data));
    }

    pub fn nextNoteEvent(self: *State) ?zigplug.NoteEvent {
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

    pub fn processAudio(self: *State, comptime Plugin: type, clap_process: [*c]const c.clap_process, start: u32, end: u32) !void {
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

        try self.plugin.process(
            self.process_block,
            if (@hasDecl(Plugin, "Parameters"))
                self.plugin.parameters.?.context
            else
                null,
        );
    }

    pub fn handleEvent(self: *State, event: *const c.clap_event_header_t) void {
        switch (event.type) {
            c.CLAP_EVENT_PARAM_VALUE => {
                const param_event: *const c.clap_event_param_value = @ptrCast(@alignCast(event));
                const param: *zigplug.Parameter = blk: {
                    if (param_event.cookie) |ptr|
                        break :blk @ptrCast(@alignCast(ptr))
                    else {
                        @branchHint(.unlikely);
                        break :blk self.plugin.parameters.?.slice[param_event.param_id];
                    }
                };

                switch (param.*) {
                    inline else => |*p| {
                        const value = @TypeOf(p.*).fromFloat(param_event.value);
                        p.set(value);
                    },
                }
            },
            c.CLAP_EVENT_PARAM_MOD => {
                const param_event: *const c.clap_event_param_mod = @ptrCast(@alignCast(event));
                const param: *zigplug.Parameter = blk: {
                    if (param_event.cookie) |ptr|
                        break :blk @ptrCast(@alignCast(ptr))
                    else {
                        @branchHint(.unlikely);
                        break :blk self.plugin.parameters.?.slice[param_event.param_id];
                    }
                };

                switch (param.*) {
                    inline else => |*p| {
                        const amount = param_event.*.amount;
                        _ = p.modulate(amount);
                    },
                }
            },
            else => {},
        }
    }
};

fn ClapPlugin(comptime Plugin: type, meta: Meta) type {
    return extern struct {
        fn init(clap_plugin: [*c]const c.clap_plugin) callconv(.c) bool {
            const state = State.fromClap(clap_plugin);
            state.plugin.log.debug("clap_plugin.init()", .{});

            return true;
        }

        fn destroy(clap_plugin: [*c]const c.clap_plugin) callconv(.c) void {
            const state = State.fromClap(clap_plugin);
            state.plugin.log.debug("clap_plugin.destroy()", .{});

            state.plugin.deinit(Plugin);
            std.heap.page_allocator.destroy(state);
            std.heap.page_allocator.destroy(@as(*const c.clap_plugin, clap_plugin));
        }

        fn activate(clap_plugin: [*c]const c.clap_plugin, sample_rate: f64, min_size: u32, max_size: u32) callconv(.c) bool {
            const state = State.fromClap(clap_plugin);
            state.plugin.log.debug("clap_plugin.activate({}, {}, {})", .{ sample_rate, min_size, max_size });

            state.plugin.sample_rate_hz = @intFromFloat(sample_rate);
            state.process_block.sample_rate_hz = state.plugin.sample_rate_hz;

            return true;
        }

        fn deactivate(clap_plugin: [*c]const c.clap_plugin) callconv(.c) void {
            const state = State.fromClap(clap_plugin);
            state.plugin.log.debug("clap_plugin.deactivate()", .{});
        }

        fn start_processing(clap_plugin: [*c]const c.clap_plugin) callconv(.c) bool {
            const state = State.fromClap(clap_plugin);
            state.plugin.log.debug("clap_plugin.start_processing()", .{});
            return true;
        }

        fn stop_processing(clap_plugin: [*c]const c.clap_plugin) callconv(.c) void {
            const state = State.fromClap(clap_plugin);
            state.plugin.log.debug("clap_plugin.stop_processing()", .{});
        }

        fn reset(clap_plugin: [*c]const c.clap_plugin) callconv(.c) void {
            const state = State.fromClap(clap_plugin);
            state.plugin.log.debug("clap_plugin.reset()", .{});
        }

        fn process(clap_plugin: [*c]const c.clap_plugin, clap_process: [*c]const c.clap_process_t) callconv(.c) c.clap_process_status {
            const state = State.fromClap(clap_plugin);

            const samples = clap_process.*.frames_count;

            var start: u32 = 0;
            var end: u32 = samples;

            const event_count = clap_process.*.in_events.*.size.?(clap_process.*.in_events);

            for (0..event_count) |i| {
                const event = clap_process.*.in_events.*.get.?(clap_process.*.in_events, @intCast(i));
                switch (event.*.type) {
                    c.CLAP_EVENT_PARAM_VALUE, c.CLAP_EVENT_PARAM_MOD => {
                        if (Plugin.meta.sample_accurate_automation) {
                            end = event.*.time;

                            state.processAudio(Plugin, clap_process, start, end) catch |e| {
                                state.plugin.log.err("error while processing: {}", .{e});
                                return c.CLAP_PROCESS_ERROR;
                            };

                            start = end;
                            end = samples;
                        }

                        state.handleEvent(event);
                    },
                    else => state.handleEvent(event),
                }
            }

            state.processAudio(Plugin, clap_process, start, end) catch |e| {
                state.plugin.log.err("error while processing: {}", .{e});
                return c.CLAP_PROCESS_ERROR;
            };

            return c.CLAP_PROCESS_CONTINUE;
        }

        fn get_extension(clap_plugin: [*c]const c.clap_plugin, id: [*c]const u8) callconv(.c) ?*const anyopaque {
            const state = State.fromClap(clap_plugin);
            const id_slice = std.mem.span(id);
            state.plugin.log.debug("clap_plugin.get_extension({s})", .{id});

            if (meta.getExtension) |getExtension|
                if (getExtension(id_slice)) |ptr|
                    return ptr;

            if (Plugin.meta.audio_ports != null) {
                if (std.mem.eql(u8, id_slice, &c.CLAP_EXT_AUDIO_PORTS))
                    return @import("extensions/audio_ports.zig").makeAudioPorts(Plugin);
            }

            if (Plugin.meta.note_ports != null) {
                if (std.mem.eql(u8, id_slice, &c.CLAP_EXT_NOTE_PORTS))
                    return @import("extensions/note_ports.zig").makeNotePorts(Plugin);
            }

            if (@hasDecl(Plugin, "Parameters")) {
                if (std.mem.eql(u8, id_slice, &c.CLAP_EXT_PARAMS))
                    return @import("extensions/parameters.zig").makeParameters(Plugin);

                if (std.mem.eql(u8, id_slice, &c.CLAP_EXT_STATE))
                    return &@import("extensions/state.zig").state;
            }

            state.plugin.log.warn("host requested unsupported extension '{s}'", .{id});

            return null;
        }

        fn on_main_thread(clap_plugin: [*c]const c.clap_plugin) callconv(.c) void {
            const state = State.fromClap(clap_plugin);
            state.plugin.log.debug("clap_plugin.on_main_thread()", .{});
        }
    };
}

// TODO: make this comptime?
inline fn makeClapDescriptor(comptime Plugin: type, comptime meta: Meta) std.mem.Allocator.Error!*const c.clap_plugin_descriptor {
    const plugin_meta: zigplug.Meta = Plugin.meta;

    const desc = try std.heap.page_allocator.create(c.clap_plugin_descriptor_t);
    desc.* = .{
        .clap_version = .{
            .major = c.CLAP_VERSION_MAJOR,
            .minor = c.CLAP_VERSION_MINOR,
            .revision = c.CLAP_VERSION_REVISION,
        },

        .id = meta.id,
        .name = plugin_meta.name,
        .vendor = plugin_meta.vendor,
        .url = plugin_meta.url,
        .manual_url = plugin_meta.manual_url orelse plugin_meta.url,
        .support_url = plugin_meta.support_url orelse plugin_meta.url,
        .version = plugin_meta.version,
        .description = plugin_meta.description,
        .features = blk: {
            const extra_features_len = if (meta.extra_features) |extra_features|
                extra_features.len
            else
                0;

            const features = try std.heap.page_allocator.alloc([*c]const u8, meta.features.len + extra_features_len + 1);
            inline for (meta.features, 0..) |feature, i|
                features[i] = feature.toString();
            if (meta.extra_features) |extra_features| {
                inline for (extra_features, meta.features.len..) |feature, i|
                    features[i] = feature;
            }

            features[meta.features.len + extra_features_len] = null;
            break :blk features.ptr;
        },
    };

    return desc;
}

fn PluginFactory(comptime Plugin: type, meta: Meta) type {
    return extern struct {
        fn get_plugin_count(_: [*c]const c.clap_plugin_factory) callconv(.c) u32 {
            return 1;
        }

        fn get_plugin_descriptor(_: [*c]const c.clap_plugin_factory, _: u32) callconv(.c) [*c]const c.clap_plugin_descriptor_t {
            return makeClapDescriptor(Plugin, meta) catch {
                return null;
            };
        }

        fn create_plugin(_: [*c]const c.clap_plugin_factory, host: [*c]const c.clap_host_t, plugin_id: [*c]const u8) callconv(.c) [*c]const c.clap_plugin_t {
            const clap_plugin = ClapPlugin(Plugin, meta);

            const plugin = zigplug.Plugin.init(Plugin) catch
                return null;

            plugin.log.debug("clap_plugin_factory.create_plugin({s})", .{plugin_id});

            std.debug.assert(host != null);

            const plugin_class = std.heap.page_allocator.create(c.clap_plugin_t) catch |e| {
                plugin.log.err("plugin allocation failed: {}", .{e});
                return null;
            };

            const plugin_data = std.heap.page_allocator.create(State) catch |e| {
                plugin.log.err("plugin allocation failed: {}", .{e});
                return null;
            };

            plugin_data.* = .{
                .plugin = plugin,
                .meta = meta,
                .host = host,
                .process_block = .{
                    .context = plugin_data,
                    .fn_nextNoteEvent = @ptrCast(&State.nextNoteEvent),
                },
            };

            if (host.*.get_extension.?(host, &c.CLAP_EXT_LOG)) |ptr| {
                plugin.log.debug("host has clap.log extension", .{});
                plugin_data.host_log = @ptrCast(@alignCast(ptr));
                plugin_data.plugin.log.* = .{
                    .context = plugin_data,
                    .logFn = hostLog,
                    .allocator = plugin_data.plugin.allocator,
                };
            }

            plugin_class.* = .{
                .desc = makeClapDescriptor(Plugin, meta) catch |e| {
                    plugin.log.err("failed to allocate descriptor: {}", .{e});
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
        fn init(_: [*c]const u8) callconv(.c) bool {
            return true;
        }

        fn deinit() callconv(.c) void {}

        fn get_factory(factory_id: [*c]const u8) callconv(.c) ?*const anyopaque {
            const id = std.mem.span(factory_id);

            if (std.mem.eql(u8, id, &c.CLAP_PLUGIN_FACTORY_ID)) {
                return &factory;
            }

            return null;
        }
    };
}

/// Export a CLAP entry point from a zigplug module.
///
/// # Example
///
/// ## `build.zig`
///
/// ```zig
/// const std = @import("std");
/// const zigplug = @import("zigplug");
///
/// pub fn build(b: *std.Build) !void {
///     const target = b.standardTargetOptions(.{});
///     const optimize = b.standardOptimizeOption(.{});
///
///     const zigplug_dep = b.dependency("zigplug", .{
///         .target = target,
///         .optimize = optimize,
///     });
///
///     const plugin = b.createModule(.{
///         .target = target,
///         .optimize = optimize,
///         .root_source_file = b.path("src/Plugin.zig"),
///         .imports = &.{
///             .{ .name = "zigplug", .module = zigplug_dep.module("zigplug") },
///         },
///     });
///
///     _ = try zigplug.addClap(b, .{
///         .name = "my-plugin",
///         .root_module = b.createModule(.{
///             .target = target,
///             .optimize = optimize,
///             .root_source_file = b.path("src/entry_clap.zig"),
///             .imports = &.{
///                 .{ .name = "Plugin", .module = plugin },
///
///                 .{ .name = "zigplug_clap", .module = zigplug.clapModule(b, target, optimize) },
///             },
///         }),
///     });
/// }
/// ```
///
/// ## `entry_clap.zig`
///
/// ```zig
/// const Plugin = @import("Plugin");
///
/// comptime {
///     @import("zigplug_clap").exportClap(Plugin, .{
///         .id = "com.example.my-plugin",
///         .features = &.{ .audio_effect, .mono, .stereo },
///     });
/// }
/// ```
pub inline fn exportClap(comptime Plugin: type, meta: Meta) void {
    const factory = PluginFactory(Plugin, meta);

    const factory_c: c.clap_plugin_factory_t = .{
        .get_plugin_count = factory.get_plugin_count,
        .get_plugin_descriptor = factory.get_plugin_descriptor,
        .create_plugin = factory.create_plugin,
    };

    const entry = PluginEntry(factory_c);

    @export(&c.clap_plugin_entry{
        .clap_version = .{
            .major = c.CLAP_VERSION_MAJOR,
            .minor = c.CLAP_VERSION_MINOR,
            .revision = c.CLAP_VERSION_REVISION,
        },

        .init = entry.init,
        .deinit = entry.deinit,
        .get_factory = entry.get_factory,
    }, .{
        .name = "clap_entry",
    });
}

comptime {
    std.testing.refAllDecls(@This());
}
