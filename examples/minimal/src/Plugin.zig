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
        .in = &.{.{
            .name = "in",
            .channels = 2,
        }},
        .out = &.{.{
            .name = "out",
            .channels = 2,
        }},
    },

    .Parameters = enum {
        gain,

        pub fn setup(self: @This()) zigplug.parameters.Parameter {
            return switch (self) {
                .gain => zigplug.parameters.makeParam(
                    .{ .float = 0 },
                    .{
                        .max = .{ .float = 0 },
                        .min = .{ .float = -100 },
                        .name = "Gain",
                        .unit = "db",
                    },
                ),
            };
        }
    },
};

pub fn plugin() zigplug.Plugin {
    return zigplug.Plugin.new(
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
    // _ = gpa.deinit(); // FIXME: unreachable
}

fn process(self: *@This(), block: zigplug.ProcessBlock) !void {
    _ = self;

    for (block.in, 0..) |in, block_i| {
        for (in, 0..) |channel, channel_i| {
            for (0..block.samples) |sample|
                block.out[block_i][channel_i][sample] = channel[sample] * 0.5;
        }
    }
}
