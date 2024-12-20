const std = @import("std");
const zigplug = @import("zigplug");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub const plugin: zigplug.Plugin = .{
    .id = "com.bandithedoge.zigplug_minimal",
    .name = "zigplug minimal",
    .vendor = "bandithedoge",
    .url = "https://bandithedoge.com/zigplug",
    .version = "0.1.0",
    .description = "Bare minimum required to build a zigplug plugin",
    .features = &.{},

    .allocator = gpa.allocator(),

    .ports = .{
        .in = &.{},
        .out = &.{},
    },

    .callbacks = .{
        .init = init,
        .deinit = deinit,
        .process = process,
    },
};

fn init(plug: *const zigplug.Plugin) void {
    _ = plug;
    gpa.init();
}

fn deinit(plug: *const zigplug.Plugin) void {
    _ = plug;
    gpa.deinit();
}

fn process(comptime plug: zigplug.Plugin, block: zigplug.ProcessBlock) zigplug.ProcessStatus {
    _ = plug;
    _ = block;
    return .ok;
}
