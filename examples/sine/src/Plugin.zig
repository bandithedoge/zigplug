const std = @import("std");

const zigplug = @import("zigplug");

// FIXME: global var bad
var gpa = std.heap.GeneralPurposeAllocator(.{}).init;

pub const meta: zigplug.Meta = .{
    .name = "zigplug sine example",
    .vendor = "bandithedoge",
    .url = "https://bandithedoge.com/zigplug",
    .version = "0.1.0",
    .description = "A zigplug example",
    .audio_ports = .{
        .in = &.{},
        .out = &.{.{
            .name = "out",
            .channels = 1,
        }},
    },
    .note_ports = .{
        .in = &.{.{
            .name = "in",
        }},
        .out = &.{},
    },
};

pub const clap_meta: @import("zigplug_clap").Meta = .{
    .id = "com.bandithedoge.zigplug_sine_example",
    // .features = &.{ .instrument, .synthesizer, .mono },
    .features = &.{},
};

pub fn plugin() !zigplug.Plugin {
    return try zigplug.Plugin.new(@This(), gpa.allocator());
}

phase: f32 = 0,
sample_rate: f32 = 0,
note: ?u8 = null,
gain: f32 = 0,

pub fn init() !@This() {
    return .{};
}

pub fn deinit(_: *@This()) void {}

pub fn process(self: *@This(), block: zigplug.ProcessBlock) !void {
    self.sample_rate = @floatFromInt(block.sample_rate);

    var start: u32 = 0;
    var end: u32 = @intCast(block.samples);

    while (block.nextNoteEvent()) |event| {
        std.debug.print("{any}: {?} at {}\n", .{ event.type, event.note, event.timing });
        switch (event.type) {
            .on => {
                self.note = event.note;
                self.gain = @floatCast(event.velocity);
            },
            .off => self.note = null,
            else => {},
        }

        end = event.timing;
        self.fillBuffer(&block, start, end);
        start = end;
    }

    self.fillBuffer(&block, start, end);
}

inline fn fillBuffer(self: *@This(), block: *const zigplug.ProcessBlock, start: u32, end: u32) void {
    for (start..end) |i| {
        for (block.out) |port| {
            for (port) |channel| {
                channel[i] = if (self.note) |n| self.sine(midiToFrequency(n)) * self.gain else 0;
            }
        }
    }
}

fn sine(self: *@This(), frequency: f32) f32 {
    const phase_delta = frequency / self.sample_rate;

    const result = @sin(std.math.tau * self.phase);

    self.phase += phase_delta;

    if (self.phase >= 1)
        self.phase -= 1;

    return result;
}

fn midiToFrequency(note: i16) f32 {
    return std.math.pow(f32, 2, @as(f32, @floatFromInt(note - 69)) / 12.0) * 440.0;
}
