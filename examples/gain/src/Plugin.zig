const std = @import("std");
const builtin = @import("builtin");

const zigplug = @import("zigplug");

var gpa = std.heap.GeneralPurposeAllocator(.{}).init;

const Parameters = enum {
    bypass,
    gain,
    pan,
    panning_law,

    const PanningLaw = enum { linear, constant_power, square_root };

    pub fn setup(self: Parameters) zigplug.Parameter {
        return switch (self) {
            .bypass => zigplug.parameters.bypass,
            .gain => .{ .float = .init(.{
                .name = "Gain",
                .default = 0,
                .min = -96,
                .max = 24,
                .unit = "db",
            }) },
            .pan => .{ .float = .init(.{
                .name = "Pan",
                .default = 0,
                .min = -1,
                .max = 1,
            }) },
            .panning_law => zigplug.parameters.choice(PanningLaw, .{
                .name = "Panning law",
                .default = .linear,
                .map = .initComptime(.{
                    .{ "Linear", .linear },
                    .{ "Constant power", .constant_power },
                    .{ "Square root", .square_root },
                }),
            }),
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
    const gain: f32 = @floatCast(std.math.pow(f64, 2, block.getParam(Parameters.gain).float.get() / 6));

    const left_gain: f32, const right_gain: f32 = blk: {
        const pan: f32 = @floatCast((block.getParam(Parameters.pan).float.get() + 1) / 2);
        switch (@as(Parameters.PanningLaw, @enumFromInt(block.getParam(Parameters.panning_law).uint.get()))) {
            .linear => break :blk .{ 1 - pan, pan },
            .constant_power => break :blk .{
                std.math.cos(0.5 * std.math.pi * pan),
                std.math.sin(0.5 * std.math.pi * pan),
            },
            .square_root => break :blk .{
                std.math.sqrt(1 - pan),
                std.math.sqrt(pan),
            },
        }
    };

    if (block.getParam(Parameters.bypass).bool.get()) {
        for (block.in, 0..) |in, block_i| {
            for (in, 0..) |channel, channel_i|
                @memcpy(block.out[block_i][channel_i], channel);
        }
    } else for (block.in, block.out) |in, out| {
        for (in[0], out[0]) |i, *o|
            o.* = i * left_gain * gain;
        for (in[1], out[1]) |i, *o|
            o.* = i * right_gain * gain;
    }
}
