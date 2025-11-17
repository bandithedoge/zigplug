const std = @import("std");
const zigplug = @import("zigplug");
const c = @import("clap_c");

pub inline fn getExtension(comptime Plugin: type, id: [:0]const u8) ?*const anyopaque {
    if (comptime Plugin.meta.audio_ports != null) {
        if (std.mem.eql(u8, id, &c.CLAP_EXT_AUDIO_PORTS))
            return @import("extensions/audio_ports.zig").makeAudioPorts(Plugin);
    }

    if (comptime Plugin.meta.note_ports != null) {
        if (std.mem.eql(u8, id, &c.CLAP_EXT_NOTE_PORTS))
            return @import("extensions/note_ports.zig").makeNotePorts(Plugin);
    }

    if (@hasDecl(Plugin, "Parameters")) {
        if (std.mem.eql(u8, id, &c.CLAP_EXT_PARAMS))
            return @import("extensions/parameters.zig").makeParameters(Plugin);

        if (std.mem.eql(u8, id, &c.CLAP_EXT_STATE))
            return &@import("extensions/state.zig").state;
    }

    zigplug.log.warn("host requested unsupported extension '{s}'", .{id});

    return null;
}

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
