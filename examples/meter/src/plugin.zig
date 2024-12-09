const std = @import("std");
const zigplug = @import("zigplug");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub const plugin: zigplug.Plugin = .{
    .id = "com.bandithedoge.zigplug",
    .name = "zigplug meter",
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
        .out = &.{},
    },

    .callbacks = .{
        .init = init,
        .deinit = deinit,
        .process = process,
    },

    .gui = .{
        .backend = zigplug.gui.backends.cairo(.{
            .render = render,
        }),
        .sample_access = true,
        .targetFps = 60,
    },

    .allocator = gpa.allocator(),
};

fn init(plug: *const zigplug.Plugin) void {
    _ = plug; // autofix

    gpa.init();
}

fn deinit(plug: *const zigplug.Plugin) void {
    _ = plug; // autofix

    gpa.deinit();
}

fn process(comptime plug: zigplug.Plugin, block: zigplug.ProcessBlock) zigplug.ProcessStatus {
    _ = plug; // autofix
    for (block.out, 0..) |buffer, buffer_i| {
        for (buffer.data, 0..) |channel, channel_i| {
            std.mem.copyForwards(f32, channel[0..buffer.samples], block.in[buffer_i].data[channel_i][0..buffer.samples]);
        }
    }
    return .ok;
}

const c = zigplug.gui.pugl.c;

var gui_state: struct {
    lock: std.Thread.RwLock = .{},
    level: [2]f32 = .{ 0.0, 0.0 },
} = .{};

// https://www.musicdsp.org/en/latest/Analysis/19-simple-peak-follower.html
const half_life = 0.1;
const very_small_float = 1.0e-30;

fn render(cr: *c.cairo_t, render_data: zigplug.gui.RenderData) !void {
    gui_state.lock.lock();
    defer gui_state.lock.unlock();

    const scalar = std.math.pow(
        f32,
        0.5,
        1.0 / (half_life * @as(f32, @floatFromInt(plugin.data.sample_rate))),
    );

    if (render_data.process_block) |block| {
        for (block.in) |buffer| {
            for (buffer.data, 0..) |channel, channel_i| {
                for (0..buffer.samples) |i| {
                    const input = @abs(channel[i]);

                    if (input >= gui_state.level[channel_i])
                        gui_state.level[channel_i] = input
                    else {
                        gui_state.level[channel_i] *= scalar;
                        if (gui_state.level[channel_i] < very_small_float)
                            gui_state.level[channel_i] = 0.0;
                    }
                }
            }
        }
    }

    c.cairo_rectangle(
        cr,
        @floatFromInt(render_data.x),
        @floatFromInt(render_data.y),
        @floatFromInt(render_data.w),
        @floatFromInt(render_data.h),
    );
    c.cairo_clip_preserve(cr);
    c.cairo_set_source_rgb(cr, 0, 0, 0);
    c.cairo_fill(cr);

    c.cairo_rectangle(
        cr,
        @floatFromInt(render_data.x),
        @floatFromInt(render_data.h),
        @floatFromInt(render_data.w / 2),
        -(gui_state.level[0] * @as(f32, @floatFromInt(render_data.h)) - @as(f32, @floatFromInt(render_data.h)) / 6.0),
    );
    if (gui_state.level[0] >= 1)
        c.cairo_set_source_rgb(cr, 1, 0, 0)
    else
        c.cairo_set_source_rgb(cr, 0, 1, 0);
    c.cairo_fill(cr);

    c.cairo_rectangle(
        cr,
        @floatFromInt(render_data.w / 2),
        @floatFromInt(render_data.h),
        @floatFromInt(render_data.w / 2),
        -(gui_state.level[1] * @as(f32, @floatFromInt(render_data.h)) - @as(f32, @floatFromInt(render_data.h)) / 6.0),
    );
    if (gui_state.level[0] >= 1)
        c.cairo_set_source_rgb(cr, 1, 0, 0)
    else
        c.cairo_set_source_rgb(cr, 0, 1, 0);
    c.cairo_fill(cr);
}
