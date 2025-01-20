const std = @import("std");
const zigplug = @import("zigplug");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub const desc: zigplug.Description = .{
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
};

pub fn init() @This() {
    return .{};
}

pub fn deinit(self: *@This()) void {
    _ = self; // autofix
    gpa.deinit();
}

pub fn process(this: *@This(), block: zigplug.ProcessBlock) zigplug.ProcessStatus {
    _ = this; // autofix
    _ = block;
    return .ok;
}
