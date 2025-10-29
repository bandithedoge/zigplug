const SineExample = @This();

const std = @import("std");

const zigplug = @import("zigplug");

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

gpa: std.heap.GeneralPurposeAllocator(.{}) = .init,

phase: f32 = 0,
sample_rate: f32 = 0,
note: ?u8 = null,
gain: f32 = 0,

pub fn init() !SineExample {
    return .{};
}

pub fn deinit(self: *SineExample) void {
    _ = self.gpa.deinit();
}

pub fn allocator(self: *SineExample) std.mem.Allocator {
    return self.gpa.allocator();
}

pub fn process(self: *SineExample, block: zigplug.ProcessBlock) !void {
    self.sample_rate = @floatFromInt(block.sample_rate_hz);

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

inline fn fillBuffer(self: *SineExample, block: *const zigplug.ProcessBlock, start: u32, end: u32) void {
    for (start..end) |i| {
        for (block.out) |port| {
            for (port) |channel| {
                channel[i] = if (self.note) |n| self.sine(midiToFrequency(n)) * self.gain else 0;
            }
        }
    }
}

fn sine(self: *SineExample, frequency: f32) f32 {
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
