const std = @import("std");
const zigplug = @import("zigplug.zig");

pub const backends = @import("backends/backends.zig");

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
};

pub const Data = struct {
    created: bool,
    sample_lock: std.Thread.RwLock = .{},
    sample_data: ?zigplug.ProcessBlock = null,
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

pub const Backend = struct {
    create: fn (comptime zigplug.Plugin) anyerror!void,
    destroy: fn (comptime zigplug.Plugin) anyerror!void,
    setParent: fn (comptime zigplug.Plugin, WindowHandle) anyerror!void,
    show: fn (comptime zigplug.Plugin, bool) anyerror!void,
    tick: fn (comptime zigplug.Plugin) anyerror!void,
    suggestTitle: ?fn (comptime zigplug.Plugin, [:0]const u8) anyerror!void,
};
