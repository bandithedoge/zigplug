const std = @import("std");
const zigplug = @import("zigplug");

var gpa = std.heap.GeneralPurposeAllocator(.{}).init;

pub const desc: zigplug.Description = .{
    .id = "com.bandithedoge.zigplug_minimal_example",
    .name = "zigplug minimal",
    .vendor = "bandithedoge",
    .url = "https://bandithedoge.com/zigplug",
    .version = "0.1.0",
    .description = "A zigplug example",
    .features = &.{},

    .ports = .{
        .in = &.{},
        .out = &.{},
    },
};

pub fn plugin() zigplug.Plugin {
    return zigplug.Plugin.new(@This(), .{
        .allocator = gpa.allocator(),
    }, .{
        .init = @ptrCast(&init),
        .deinit = @ptrCast(&deinit),
        .process = @ptrCast(&process),
    });
}

fn init() !*@This() {
    const self = try gpa.allocator().create(@This());
    self.* = .{};
    return self;
}

fn deinit(self: *@This()) void {
    gpa.allocator().destroy(self);
    _ = gpa.deinit();
}

fn process(this: *@This(), block: zigplug.ProcessBlock) zigplug.ProcessStatus {
    _ = this; // autofix
    _ = block;
    return .ok;
}
