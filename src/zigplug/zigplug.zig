const std = @import("std");

pub const parameters = @import("parameters.zig");
pub const Parameter = parameters.Parameter;

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
    parameters: ?[]const Parameter,

    pub fn getParam(self: *const ProcessBlock, param: anytype) *const Parameter {
        switch (@typeInfo(@TypeOf(param))) {
            .@"enum" => {
                if (self.parameters) |params|
                    return &params[@intFromEnum(param)];

                @panic("getParam() was called but there are no parameters");
            },
            else => @compileError("getParam() must be called with an enum"),
        }
    }
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
    context: *anyopaque,
    vtable: struct {
        deinit: *const fn (*anyopaque) void,
        process: *const fn (*anyopaque, ProcessBlock) anyerror!void,
    },

    allocator: std.mem.Allocator,

    pub fn new(T: type, allocator: std.mem.Allocator) !Plugin {
        return .{
            .context = try T.init(),
            .vtable = .{
                .deinit = @ptrCast(&T.deinit),
                .process = @ptrCast(&T.process),
            },
            .allocator = allocator,
        };
    }

    pub inline fn deinit(self: *Plugin) void {
        self.vtable.deinit(self.context);
    }

    pub inline fn process(self: *Plugin, block: ProcessBlock) !void {
        try self.vtable.process(self.context, block);
    }
};

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
