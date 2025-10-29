const ClapExtExample = @This();

const std = @import("std");

const zigplug = @import("zigplug");
const clap = @import("zigplug_clap");

pub const meta: zigplug.Meta = .{
    .name = "zigplug clap extension example",
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

fn getExtension(id: [:0]const u8) ?*const anyopaque {
    // let's implement the "note-name" extension, which is not supported in zigplug (yet?).
    // we can test this in reaper for example
    //
    // https://github.com/free-audio/clap/blob/main/include/clap/ext/note-name.h
    if (std.mem.eql(u8, id, &clap.c.CLAP_EXT_NOTE_NAME)) {
        const ext = struct {
            pub fn count(_: [*c]const clap.c.clap_plugin_t) callconv(.c) u32 {
                return 1;
            }

            pub fn get(clap_plugin: [*c]const clap.c.clap_plugin_t, index: u32, note_name: [*c]clap.c.clap_note_name_t) callconv(.c) bool {
                // you can use this to access your plugin's state
                const self = clap.pluginFromClap(clap_plugin, ClapExtExample);
                _ = self;

                if (index == 0) {
                    // let's set the name of every note to some string
                    note_name.* = .{
                        // zig initializes c structs with `std.mem.zeroes` so we don't have to deal with an undefined
                        // name value
                        .port = -1,
                        .key = -1,
                        .channel = -1,
                    };
                    std.mem.copyForwards(u8, &note_name.*.name, "Hello world... i mean note");
                    return true;
                }
                return false;
            }
        };
        return &clap.c.clap_plugin_note_name_t{
            .count = ext.count,
            .get = ext.get,
        };
    }
    return null;
}

pub const clap_meta: clap.Meta = .{
    .id = "com.bandithedoge.zigplug_clap_ext_example",
    .features = &.{ .instrument, .synthesizer, .mono },
    .getExtension = getExtension,
};

gpa: std.heap.GeneralPurposeAllocator(.{}) = .init,

phase: f32 = 0,
sample_rate_hz: f32 = 0,
note: ?u8 = null,
gain: f32 = 0,

pub fn init() !ClapExtExample {
    return .{};
}

pub fn deinit(self: *ClapExtExample) void {
    _ = self.gpa.deinit();
}

pub fn allocator(self: *ClapExtExample) std.mem.Allocator {
    return self.gpa.allocator();
}

pub fn process(self: *ClapExtExample, block: zigplug.ProcessBlock) !void {
    self.sample_rate_hz = @floatFromInt(block.sample_rate_hz);

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

inline fn fillBuffer(self: *ClapExtExample, block: *const zigplug.ProcessBlock, start: u32, end: u32) void {
    for (start..end) |i| {
        for (block.out) |port| {
            for (port) |channel| {
                channel[i] = if (self.note) |n| self.sine(midiToFrequency(n)) * self.gain else 0;
            }
        }
    }
}

fn sine(self: *ClapExtExample, frequency: f32) f32 {
    const phase_delta = frequency / self.sample_rate_hz;

    const result = @sin(std.math.tau * self.phase);

    self.phase += phase_delta;

    if (self.phase >= 1)
        self.phase -= 1;

    return result;
}

fn midiToFrequency(note: i16) f32 {
    return std.math.pow(f32, 2, @as(f32, @floatFromInt(note - 69)) / 12.0) * 440.0;
}
