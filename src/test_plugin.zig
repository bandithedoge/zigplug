const std = @import("std");
const zigplug = @import("zigplug.zig");
const clap = @import("clap/adapter.zig");

var state: struct {
    phase: f32,
} = undefined;

const plugin: zigplug.Plugin = .{
    .id = "com.bandithedoge.zigplug",
    .name = "zigplug",
    .vendor = "bandithedoge",
    .url = "https://bandithedoge.com/zigplug",
    .version = "0.0.1",
    .description = "zigplug test",
    .features = &.{ .effect, .utility },
    .manual_url = null,
    .support_url = null,

    .ports = .{
        .in = &.{
            .{
                .name = "Audio Input",
                .channels = 2,
            },
        },
        .out = &.{
            .{
                .name = "Audio Output",
                .channels = 2,
            },
        },
    },

    .callbacks = .{
        .init = init,
        .deinit = deinit,
        .process = process,
    },
};

export const clap_entry = clap.clap_entry(plugin);

fn init(plugin_data: *const zigplug.PluginData) void {
    _ = plugin_data; // autofix
    state.phase = 0.0;
}

fn deinit(plugin_data: *const zigplug.PluginData) void {
    _ = plugin_data; // autofix
}

fn process(plugin_data: *const zigplug.PluginData, block: zigplug.ProcessBlock) zigplug.ProcessStatus {
    for (block.out) |buffer| {
        for (0..buffer.channels) |channel| {
            for (0..buffer.samples) |sample| {
                buffer.data[channel][sample] = @sin(state.phase * 2.0 * std.math.pi) * 0.2;
                state.phase += 440.0 / @as(f32, @floatFromInt(plugin_data.sample_rate));
                state.phase -= @floor(state.phase);
            }
        }
    }
    return .ok;
}
