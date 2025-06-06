const std = @import("std");
const builtin = @import("builtin");

const zigplug = @import("zigplug");

var gpa = std.heap.GeneralPurposeAllocator(.{}).init;

const Parameters = enum {
    bypass,
    gain,

    pub fn setup(self: Parameters) zigplug.Parameter {
        return switch (self) {
            .bypass => zigplug.parameters.Bypass,
            .gain => .{ .float = .init(.{
                .name = "Gain",
                .default = 0,
                .min = -96,
                .max = 24,
                .unit = "db",
            }) },
        };
    }
};

pub const desc: zigplug.Description = .{
    .id = "com.bandithedoge.zigplug_minimal_example",
    .name = "zigplug minimal",
    .vendor = "bandithedoge",
    .url = "https://bandithedoge.com/zigplug",
    .version = "0.1.0",
    .description = "A zigplug example",
    .ports = .{
        .in = &.{.{
            .name = "in",
            .channels = 2,
        }},
        .out = &.{.{
            .name = "out",
            .channels = 2,
        }},
    },
    .Parameters = Parameters,
};

pub fn plugin() !zigplug.Plugin {
    return try zigplug.Plugin.new(
        .{
            .allocator = gpa.allocator(),
        },
        .{
            .init = @ptrCast(&init),
            .deinit = @ptrCast(&deinit),
            .process = @ptrCast(&process),
        },
    );
}

fn init() !*@This() {
    const self = try gpa.allocator().create(@This());
    self.* = .{};
    return self;
}

fn deinit(self: *@This()) void {
    gpa.allocator().destroy(self);
}

fn process(self: *@This(), block: zigplug.ProcessBlock) !void {
    _ = self;
    const amplitude: f32 = @floatCast(std.math.pow(f64, 2, block.getParam(Parameters.gain).float.get() / 6));

    if (block.getParam(Parameters.bypass).bool.get()) {
        for (block.in, 0..) |in, block_i| {
            for (in, 0..) |channel, channel_i|
                @memcpy(block.out[block_i][channel_i], channel);
        }
    } else for (block.in, 0..) |in, block_i| {
        for (in, 0..) |channel, channel_i| {
            for (channel, 0..block.samples) |input, sample|
                block.out[block_i][channel_i][sample] = input * amplitude;
        }
    }
}
