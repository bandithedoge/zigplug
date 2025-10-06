const std = @import("std");

const zigplug = @import("zigplug");

// FIXME: global var bad
var gpa = std.heap.GeneralPurposeAllocator(.{}).init;

pub const Parameters = struct {
    const PanningLaw = enum { linear, constant_power, square_root };

    bypass: zigplug.Parameter = .bypass,

    gain: zigplug.Parameter = .{ .float = .init(.{
        .name = "Gain",
        .default = 0,
        .min = -96,
        .max = 24,
        .unit = "db",
    }) },

    pan: zigplug.Parameter = .{ .float = .init(.{
        .name = "Pan",
        .default = 0,
        .min = -1,
        .max = 1,
    }) },

    panning_law: zigplug.Parameter = .choice(PanningLaw, .{
        .name = "Panning law",
        .default = .constant_power,
        .map = .initComptime(.{
            .{ "Linear", .linear },
            .{ "Constant power", .constant_power },
            .{ "Square root", .square_root },
        }),
    }),
};

pub const meta: zigplug.Meta = .{
    .id = "com.bandithedoge.zigplug_gain_example",
    .name = "zigplug gain example",
    .vendor = "bandithedoge",
    .url = "https://bandithedoge.com/zigplug",
    .version = "0.1.0",
    .description = "A zigplug example",
    .audio_ports = .{
        .in = &.{.{
            .name = "in",
            .channels = 2,
        }},
        .out = &.{.{
            .name = "out",
            .channels = 2,
        }},
    },

    .sample_accurate_automation = true,
};

pub fn plugin() !zigplug.Plugin {
    return try zigplug.Plugin.new(@This(), gpa.allocator());
}

pub fn init() !@This() {
    return .{};
}

pub fn deinit(_: *@This()) void {}

pub fn process(self: *@This(), block: zigplug.ProcessBlock, params: *const Parameters) !void {
    _ = self;

    if (params.bypass.bool.get()) {
        for (block.in, 0..) |in, block_i| {
            for (in, 0..) |channel, channel_i|
                @memcpy(block.out[block_i][channel_i], channel);
        }
    } else {
        const gain: f32 = @floatCast(std.math.pow(f64, 2, params.gain.float.get() / 6));

        const left_gain: f32, const right_gain: f32 = blk: {
            const pan: f32 = @floatCast((params.pan.float.get() + 1) / 2);
            switch (@as(Parameters.PanningLaw, @enumFromInt(params.panning_law.uint.get()))) {
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

        for (block.in, block.out) |in, out|
            for (0..block.samples) |i| {
                out[0][i] = in[0][i] * left_gain * gain;
                out[1][i] = in[1][i] * right_gain * gain;
            };
    }
}
