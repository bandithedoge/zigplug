const std = @import("std");

pub const parameters = @import("parameters.zig");
pub const Parameter = parameters.Parameter;

pub const NoteEvent = struct {
    type: enum { on, off, choke, end },
    /// From C-1 to G9. 60 is middle C, `null` means wildcard
    note: ?u8,
    channel: ?u5,
    timing: u32,
    velocity: f64,
};

pub const ProcessBlock = struct {
    context: *anyopaque,
    fn_nextNoteEvent: *const fn (*anyopaque) ?NoteEvent,

    in: []const []const []const f32 = &.{},
    out: [][][]f32 = &.{},
    samples: usize = 0,
    sample_rate_hz: u32 = 0,

    pub fn nextNoteEvent(self: *const ProcessBlock) ?NoteEvent {
        return self.fn_nextNoteEvent(self.context);
    }
};

pub const ProcessStatus = enum {
    ok,
    failed,
};

pub const AudioPorts = struct {
    pub const Port = struct {
        name: [:0]const u8, // TODO: make this optional
        channels: u32,
    };

    in: []const Port,
    out: []const Port,
};

pub const NotePorts = struct {
    pub const Port = struct {
        name: [:0]const u8,
    };

    in: []const Port,
    out: []const Port,
};

pub const Meta = struct {
    name: [:0]const u8,
    vendor: [:0]const u8,
    url: [:0]const u8,
    version: [:0]const u8,
    description: [:0]const u8,
    manual_url: ?[:0]const u8 = null,
    support_url: ?[:0]const u8 = null,

    audio_ports: ?AudioPorts = null,
    note_ports: ?NotePorts = null,

    /// When enabled, the signal is split into smaller buffers of different sizes so that every parameter change is
    /// accounted for. This slightly increases CPU usage and potentially reduces the effectiveness of optimizations like
    /// SIMD in return for more accurate parameter automation.
    ///
    /// Has no effect when the plugin has no parameters
    // TODO: set this for individual parameters
    sample_accurate_automation: bool = false,
};

pub const Plugin = @import("Plugin.zig");

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
