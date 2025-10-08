const std = @import("std");

pub const parameters = @import("parameters.zig");
pub const Parameter = parameters.Parameter;

pub const log = std.log.scoped(.zigplug);

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
    sample_rate: u32 = 0,

    pub fn nextNoteEvent(self: *const ProcessBlock) ?NoteEvent {
        return self.fn_nextNoteEvent(self.context);
    }
};

pub const ProcessStatus = enum {
    ok,
    failed,
};

pub const PluginData = struct {
    /// Hz
    sample_rate: u32 = 0,
    plugin: Plugin,

    pub fn cast(ptr: ?*anyopaque) *PluginData {
        return @ptrCast(@alignCast(ptr));
    }
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

pub const Plugin = struct {
    context: *anyopaque,

    vtable: struct {
        // TODO: verify types
        deinit: *const fn (*anyopaque) void,
        process: *const fn (*anyopaque, ProcessBlock, ?*const anyopaque) anyerror!void,
    },

    allocator: std.mem.Allocator,
    parameters: ?*anyopaque = null,

    // TODO: allow setting an allocator *after* init
    // TODO: validate parameters struct
    pub fn new(comptime T: type, allocator: std.mem.Allocator) !Plugin {
        const context = try allocator.create(T);
        context.* = try T.init();
        return .{
            .context = context,
            .vtable = .{
                .deinit = @ptrCast(&T.deinit),
                .process = @ptrCast(&T.process),
            },
            .allocator = allocator,
        };
    }

    pub inline fn deinit(self: *Plugin, comptime P: type) void {
        self.vtable.deinit(self.context);

        const plugin: *P = @ptrCast(@alignCast(self.context));
        self.allocator.destroy(plugin);
    }

    pub inline fn process(self: *Plugin, block: ProcessBlock, params: ?*const anyopaque) !void {
        try self.vtable.process(self.context, block, params);
    }
};

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
