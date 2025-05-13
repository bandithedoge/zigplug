const std = @import("std");
pub const parameters = @import("parameters.zig");

pub const log = std.log.scoped(.zigplug);

pub const Port = struct {
    name: [:0]const u8, // TODO: make this optional
    channels: u32,
};

pub const ProcessBlock = struct {
    in: []const []const []const f32,
    out: [][][]f32,
    samples: usize,
    sample_rate: u32,
    // TODO: the user shouldn't have to cast this themselves
    parameters: ?*anyopaque,
};

pub const ProcessStatus = enum {
    ok,
    failed,
};

pub const PluginData = struct {
    /// Hz
    sample_rate: u32,
    plugin: Plugin,

    pub fn cast(ptr: ?*anyopaque) *PluginData {
        return @ptrCast(@alignCast(ptr));
    }
};

pub const Ports = struct {
    in: []const Port,
    out: []const Port,
};

pub const Description = struct {
    id: [:0]const u8,
    name: [:0]const u8,
    vendor: [:0]const u8,
    url: [:0]const u8,
    version: [:0]const u8,
    description: [:0]const u8,
    // TODO: implement features
    manual_url: ?[:0]const u8 = null,
    support_url: ?[:0]const u8 = null,

    ports: Ports,

    Parameters: ?type = null,
};

// TODO: make descriptor a member here
pub const Plugin = struct {
    const Callbacks = struct {
        init: *const fn () anyerror!*anyopaque,
        deinit: *const fn (*anyopaque) void,
        process: *const fn (*anyopaque, ProcessBlock) anyerror!void,
    };

    const Options = struct {
        allocator: std.mem.Allocator,
    };

    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    callbacks: Callbacks,

    pub fn new(options: Options, callbacks: Callbacks) !Plugin {
        return .{
            .ptr = try callbacks.init(),
            .allocator = options.allocator,
            .callbacks = callbacks,
        };
    }

    pub inline fn deinit(self: *Plugin) void {
        self.callbacks.deinit(self.ptr);
    }

    pub inline fn process(self: *Plugin, block: ProcessBlock) !void {
        try self.callbacks.process(self.ptr, block);
    }
};

pub inline fn fieldInfoByIndex(comptime T: type, index: usize) std.builtin.Type.StructField {
    return std.meta.fieldInfo(T, @enumFromInt(index));
}

pub inline fn fieldByIndex(comptime T: type, ptr: *anyopaque, index: usize) *std.meta.fieldInfo(T, @enumFromInt(index)).type {
    const field = fieldInfoByIndex(T, index);
    return &@field(@as(*T, @ptrCast(@alignCast(ptr))), field.name);
}

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
