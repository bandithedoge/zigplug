const std = @import("std");
const zigplug = @import("zigplug");
const options = @import("zigplug_options");
const clap = @import("clap_adapter");
const c = @import("clap_c");

pub inline fn getExtension(comptime Plugin: type, id: [:0]const u8) ?*const anyopaque {
    if (std.mem.eql(u8, id, &c.CLAP_EXT_AUDIO_PORTS)) {
        return @import("extensions/audio_ports.zig").getExtension(Plugin);
    }

    if (comptime Plugin.desc.Parameters != null)
        if (std.mem.eql(u8, id, &c.CLAP_EXT_PARAMS))
            return @import("extensions/parameters.zig").getExtension(Plugin);

    zigplug.log.warn("host requested unsupported extension '{s}'", .{id});

    return null;
}
