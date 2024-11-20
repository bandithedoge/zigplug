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

pub const Backend = struct {
    create: fn (comptime zigplug.Plugin) anyerror!void,
    destroy: fn (comptime zigplug.Plugin) anyerror!void,
    setParent: fn (comptime zigplug.Plugin, WindowHandle) anyerror!void,
    show: fn (comptime zigplug.Plugin, bool) anyerror!void,
    tick: fn (comptime zigplug.Plugin) anyerror!void,
    suggestTitle: ?fn (comptime zigplug.Plugin, [:0]const u8) anyerror!void,
};
