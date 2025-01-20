const std = @import("std");
const zigplug = @import("zigplug.zig");
pub const pugl = @import("pugl.zig");

pub const WindowHandle = union(enum) {
    x11: u64,
    cocoa: *anyopaque,
    win32: *anyopaque,
};

pub const RenderData = struct {
    x: i32,
    y: i32,
    w: u32,
    h: u32,
    process_block: ?zigplug.ProcessBlock = null,
    parameters: []zigplug.parameters.Parameter,
    plugin_data: *const zigplug.PluginData,

    pub fn getParam(self: *const RenderData, id: anytype) zigplug.parameters.ParameterType {
        return self.parameters[@intFromEnum(id)].get();
    }

    pub fn setParam(self: *RenderData, id: anytype, value: zigplug.parameters.ParameterType) void {
        self.parameters[@intFromEnum(id)].set(value);
    }
};

pub const Data = struct {
    created: bool,
    visible: bool,
    sample_lock: std.Thread.Mutex = .{},
    sample_data: ?zigplug.ProcessBlock = null,
    requestResize: ?*const fn (*anyopaque, u32, u32) bool = null,
};

pub const Options = struct {
    backend: Backend,

    resizable: bool = false,
    keep_aspect: bool = true,
    default_width: u16 = 800,
    default_height: u16 = 600,
    min_width: ?u16 = null,
    min_height: ?u16 = null,
    sample_access: bool = false,
    targetFps: ?f32 = null,
};

pub const Event = enum { Idle, ParamChanged, StateChanged, SizeChanged };

pub const Size = struct {
    w: u32,
    h: u32,
};

pub const Backend = struct {
    create: fn (comptime type, *zigplug.PluginData) anyerror!void,
    destroy: fn (comptime type) anyerror!void,
    setParent: fn (comptime type, WindowHandle) anyerror!void,
    show: fn (comptime type, bool) anyerror!void,
    tick: fn (comptime type, Event) anyerror!void,
    suggestTitle: ?fn (comptime type, [:0]const u8) anyerror!void,
    setSize: ?fn (comptime type, u32, u32) anyerror!void,
    getSize: ?fn (comptime type) anyerror!Size,
};

pub const backends = struct {
    pub const openGl = pugl.openGl;
    pub const cairo = pugl.cairo;
};
