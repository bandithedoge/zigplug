const std = @import("std");

const zigplug = @import("zigplug");

// FIXME: global var bad
var gpa = std.heap.GeneralPurposeAllocator(.{}).init;

pub const desc: zigplug.Description = .{
    .id = "com.bandithedoge.zigplug_sine_example",
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

pub fn plugin() !zigplug.Plugin {
    return try zigplug.Plugin.new(@This(), gpa.allocator());
}

phase: f32 = 0,
sample_rate: f32 = 0,
note: ?u8 = null,
gain: f32 = 0,

pub fn init() !*@This() {
    const self = try gpa.allocator().create(@This());
    self.* = .{};
    return self;
}

pub fn deinit(self: *@This()) void {
    gpa.allocator().destroy(self);
}

pub fn process(self: *@This(), block: zigplug.ProcessBlock, _: *const anyopaque) !void {
    self.sample_rate = @floatFromInt(block.sample_rate);

    var event: ?zigplug.NoteEvent = null;

    for (0..block.samples) |i| {
        while (true) {
            event = block.nextNoteEvent();
            if (event) |e| {
                std.debug.print("{any} {?}\n", .{ e.type, e.note });
                if (e.timing == i)
                    switch (e.type) {
                        .on => {
                            self.note = e.note;
                            self.gain = @floatCast(e.velocity);
                        },
                        .off => self.note = null,
                        else => {},
                    }
                else
                    break;
            } else break;
        }

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
