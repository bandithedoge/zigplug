const std = @import("std");
const zigplug = @import("zigplug");

var state: struct {
    phase: f32,
} = undefined;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub const plugin: zigplug.Plugin = .{
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

    .Parameters = enum {
        gain,
        frequency,
        mute,

        pub fn setup(self: @This()) zigplug.parameters.Parameter {
            return switch (self) {
                .gain => zigplug.parameters.makeParam(.{ .float = 1.0 }, .{
                    .name = "Gain",
                }),
                .frequency => zigplug.parameters.makeParam(.{ .uint = 440 }, .{
                    .name = "Frequency",
                    .min = .{ .uint = 0 },
                    .max = .{ .uint = 20000 },
                    .unit = "Hz",
                }),
                .mute => zigplug.parameters.makeParam(.{ .bool = false }, .{
                    .name = "Mute",
                }),
            };
        }
    },

    .gui = .{
        .backend = zigplug.gui.backends.Cairo.backend(.{
            .render = render,
        }),
    },

    .allocator = gpa.allocator(),
};

fn init(plug: *const zigplug.Plugin) void {
    _ = plug; // autofix

    gpa.init();

    state.phase = 0.0;
}

fn deinit(plug: *const zigplug.Plugin) void {
    _ = plug; // autofix

    gpa.deinit();
}

fn process(comptime plug: zigplug.Plugin, block: zigplug.ProcessBlock) zigplug.ProcessStatus {
    for (block.out) |buffer| {
        for (buffer.data) |channel| {
            for (0..buffer.samples) |sample| {
                // TODO: write a better sine wave example...
                channel[sample] = if (plug.getParam(.mute).bool)
                    0
                else
                    @sin(state.phase * 2.0 * std.math.pi) * 0.2 * plug.getParam(.gain).float;

                state.phase += @as(f32, @floatFromInt(plug.getParam(.frequency).uint)) /
                    @as(f32, @floatFromInt(plug.data.sample_rate));
                state.phase -= @floor(state.phase);
            }
        }
    }
    return .ok;
}

const c = zigplug.gui.backends.Cairo.c;

fn render(cr: *c.cairo_t, render_data: zigplug.gui.RenderData) !void {
    c.cairo_rectangle(
        cr,
        @floatFromInt(render_data.x),
        @floatFromInt(render_data.y),
        @floatFromInt(render_data.w),
        @floatFromInt(render_data.h),
    );
    c.cairo_clip_preserve(cr);
    c.cairo_set_source_rgb(cr, 0, 1, 0);
    c.cairo_fill(cr);

    const label = "zigplug sucks";
    var extents: c.cairo_text_extents_t = undefined;
    c.cairo_set_font_size(cr, 32);
    c.cairo_text_extents(cr, label, &extents);
    c.cairo_move_to(
        cr,
        @as(f64, @floatFromInt(render_data.w / 2)) - extents.width / 2.0,
        @as(f64, @floatFromInt(render_data.h / 2)) - extents.height / 2.0,
    );
    c.cairo_set_source_rgba(cr, 0, 0, 0, 1);
    c.cairo_show_text(cr, label);
}
