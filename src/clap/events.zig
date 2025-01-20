const zigplug = @import("zigplug");
const clap = @import("./adapter.zig");
const c = @import("clap_c");

pub fn syncMainToAudio(comptime Plugin: type, data: *clap.Data, out: [*c]const c.clap_output_events_t) void {
    data.plugin_data.param_lock.lock();
    defer data.plugin_data.param_lock.unlock();

    for (0..@typeInfo(Plugin.desc.Parameters.?).Enum.fields.len) |i| {
        const param = &data.plugin_data.parameters.items[i];
        if (param.main_changed) {
            param.set(param.main_value);
            param.main_changed = false;

            const event: c.clap_event_param_value_t = .{
                .header = .{
                    .type = c.CLAP_EVENT_PARAM_VALUE,
                    .flags = 0,
                    .size = @sizeOf(c.clap_event_param_value_t),
                    .space_id = c.CLAP_CORE_EVENT_SPACE_ID,
                    .time = 0,
                },
                .param_id = @intCast(i),
                .channel = -1,
                .cookie = null,
                .key = -1,
                .note_id = -1,
                .port_index = -1,
                .value = param.get().toFloat(),
            };

            _ = out.*.try_push.?(out, &event.header);
        }
    }
}

pub fn syncAudioToMain(comptime Plugin: type, data: *clap.Data) bool {
    var any_changed = false;

    data.plugin_data.param_lock.lock();
    defer data.plugin_data.param_lock.unlock();

    for (0..@typeInfo(Plugin.desc.Parameters.?).Enum.fields.len) |i| {
        const param = &data.plugin_data.parameters.items[i];
        if (param.changed) {
            param.main_value = param.get();
            param.changed = false;
            any_changed = true;
        }
    }

    return any_changed;
}

pub fn processEvent(Plugin: type, clap_plugin: [*c]const c.clap_plugin_t, event: *const c.clap_event_header_t) void {
    const data = clap.Data.cast(clap_plugin);
    if (event.space_id == c.CLAP_CORE_EVENT_SPACE_ID) {
        switch (event.type) {
            c.CLAP_EVENT_PARAM_VALUE => {
                data.plugin_data.param_lock.lock();
                defer data.plugin_data.param_lock.unlock();

                const value_event: *const c.clap_event_param_value_t = @ptrCast(@alignCast(event));
                zigplug.log.debug("param {} value: {}", .{ value_event.param_id, value_event.value });

                const param = &data.plugin_data.parameters.items[value_event.param_id];
                param.value.fromFloat(value_event.value);
                param.changed = true;

                if (comptime Plugin.desc.gui) |gui| {
                    if (data.plugin_data.gui.?.visible)
                        gui.backend.tick(Plugin, .ParamChanged) catch {};
                }
            },
            else => {},
        }
    }
}
