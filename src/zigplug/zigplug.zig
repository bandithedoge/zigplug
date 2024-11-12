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
};

pub const ProcessStatus = enum {
    ok,
    failed,
};

pub const PluginData = struct {
    /// hz
    sample_rate: u32,
    mutex: std.Thread.Mutex,
    parameters: std.ArrayList(parameters.Parameter),
    gui_created: bool = false,
};

pub const GuiOptions = struct {
    backend: gui.Backend,

    resizable: bool = false,
    keep_aspect: bool = true,
    default_width: u16 = 800,
    default_height: u16 = 600,
    min_width: ?u16 = null,
    min_height: ?u16 = null,
};

pub const Plugin = struct {
    allocator: std.mem.Allocator,

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

    ports: struct {
        in: []const Port,
        out: []const Port,
    },

    callbacks: struct {
        init: fn (*const Plugin) void,
        deinit: fn (*const Plugin) void,
        setupParameter: fn (type, u32) parameters.Parameter,
        // TODO: process events
        process: fn (*const Plugin, ProcessBlock) ProcessStatus,
    },

    Parameters: type,

    gui: ?GuiOptions = null,

    data: *PluginData = &plugin_data,

    pub var plugin_data: PluginData = undefined;

    pub fn getParam(self: *const Plugin, id: self.Parameters) parameters.ParameterType {
        plugin_data.mutex.lock();
        defer plugin_data.mutex.unlock();

        const result = self.data.parameters.items[@intFromEnum(id)].get();
        return result;
    }
};

pub const log = std.log.scoped(.zigplug);