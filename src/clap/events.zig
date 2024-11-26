const zigplug = @import("zigplug");
const clap = @import("c");

pub fn syncMainToAudio(comptime plugin: zigplug.Plugin, out: [*c]const clap.clap_output_events_t) void {
    plugin.data.param_lock.lock();
    defer plugin.data.param_lock.unlock();

    for (0..@typeInfo(plugin.Parameters.?).@"enum".fields.len) |i| {
        const param = &plugin.data.parameters.items[i];
        if (param.main_changed) {
            param.set(param.main_value);
            param.main_changed = false;

            const event: clap.clap_event_param_value_t = .{
                .header = .{
                    .type = clap.CLAP_EVENT_PARAM_VALUE,
                    .flags = 0,
                    .size = @sizeOf(clap.clap_event_param_value_t),
                    .space_id = clap.CLAP_CORE_EVENT_SPACE_ID,
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

pub fn syncAudioToMain(comptime plugin: zigplug.Plugin) bool {
    var any_changed = false;

    plugin.data.param_lock.lock();
    defer plugin.data.param_lock.unlock();

    for (0..@typeInfo(plugin.Parameters.?).@"enum".fields.len) |i| {
        const param = &plugin.data.parameters.items[i];
        if (param.changed) {
            param.main_value = param.get();
            param.changed = false;
            any_changed = true;
        }
    }

    return any_changed;
}

pub fn processEvent(comptime plugin: zigplug.Plugin, event: *const clap.clap_event_header_t) void {
    if (event.space_id == clap.CLAP_CORE_EVENT_SPACE_ID) {
        switch (event.type) {
            clap.CLAP_EVENT_PARAM_VALUE => {
                plugin.data.param_lock.lock();
                defer plugin.data.param_lock.unlock();

                const value_event: *const clap.clap_event_param_value_t = @ptrCast(@alignCast(event));
                zigplug.log.debug("param {} value: {}", .{ value_event.param_id, value_event.value });

                const param = &plugin.data.parameters.items[value_event.param_id];
                param.value.fromFloat(value_event.value);
                param.changed = true;
            },
            else => {},
        }
    }
}
