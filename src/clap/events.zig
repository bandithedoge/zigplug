const clap = @import("c.zig");
const zigplug = @import("../zigplug.zig");

pub fn processEvent(plugin: *const zigplug.Plugin, event: *const clap.clap_event_header_t) void {
    if (event.space_id == clap.CLAP_CORE_EVENT_SPACE_ID) {
        switch (event.type) {
            clap.CLAP_EVENT_PARAM_VALUE => {
                plugin.data.mutex.lock();
                defer plugin.data.mutex.unlock();

                const param_event: *const clap.clap_event_param_value_t = @ptrCast(@alignCast(event));
                zigplug.log.debug("param {} value: {}", .{ param_event.param_id, param_event.value });
                plugin.data.parameters.items[param_event.param_id].value.fromFloat(param_event.value);
            },
            else => {},
        }
    }
}
