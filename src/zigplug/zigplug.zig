const std = @import("std");
pub const parameters = @import("parameters.zig");
pub const gui = @import("gui.zig");

pub const Feature = enum { instrument, effect, note_effect, note_detector, analyzer, synthesizer, sampler, drum, drum_machine, filter, phaser, equalizer, deesser, phase_vocoder, granular, frequency_shifter, pitch_shifter, distortion, transient_shaper, compressor, expander, gate, limiter, flanger, chorus, delay, reverb, tremolo, glitch, utility, pitch_correction, restoration, multi_effects, mixing, mastering, mono, stereo, surround, ambisonic };

pub const Port = struct {
    name: [:0]const u8,
    channels: u32,
};

pub const ProcessBuffer = struct {
    data: [][*]f32, // TODO: use a slice for sample data
    samples: u32,
};

pub const ProcessBlock = struct {
    in: []ProcessBuffer,
    out: []ProcessBuffer,
    sample_rate: u32,
};

pub const ProcessStatus = enum {
    ok,
    failed,
};

pub const PluginData = struct {
    /// hz
    sample_rate: u32,
    param_lock: std.Thread.Mutex,
    parameters: std.ArrayList(parameters.Parameter),

    gui: ?gui.Data = null,

    pub fn cast(ptr: ?*anyopaque) *PluginData {
        return @ptrCast(@alignCast(ptr));
    }
};

pub const Ports = struct {
    in: []const Port,
    out: []const Port,
};

pub const Description = struct {
    id: [:0]const u8,
    name: [:0]const u8,
    vendor: [:0]const u8,
    url: [:0]const u8,
    version: [:0]const u8,
    description: [:0]const u8,
    /// TODO: implement features
    features: []const Feature,
    manual_url: ?[:0]const u8 = null,
    support_url: ?[:0]const u8 = null,

    ports: Ports,

    Parameters: ?type = null,

    gui: ?gui.Options = null,
};

pub const Plugin = struct {
    const Callbacks = struct {
        init: *const fn () *anyopaque,
        deinit: *const fn (*anyopaque) void,
        process: *const fn (*anyopaque, ProcessBlock) ProcessStatus,
    };

    const Options = struct {
        allocator: std.mem.Allocator,
    };

    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    callbacks: Callbacks,

    pub fn new(comptime T: type, options: Options, callbacks: Callbacks) Plugin {
        _ = T; // autofix
        const ptr = callbacks.init();
        return .{
            .ptr = ptr,
            .allocator = options.allocator,
            .callbacks = callbacks,
        };
    }

    pub fn deinit(self: *Plugin) void {
        self.callbacks.deinit(self.ptr);
    }

    pub fn process(self: *Plugin, block: ProcessBlock) ProcessStatus {
        return self.callbacks.process(self.ptr, block);
    }
};

pub const log = std.log.scoped(.zigplug);
