const std = @import("std");
const zigplug = @import("zigplug");

var gpa = std.heap.GeneralPurposeAllocator(.{}).init;

pub const desc: zigplug.Description = .{
    .id = "com.bandithedoge.zigplug_meter_example",
    .name = "zigplug meter example",
    .vendor = "bandithedoge",
    .url = "https://bandithedoge.com/zigplug",
    .version = "0.0.1",
    .description = "A zigplug example",
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

    .gui = .{
        .backend = zigplug.gui.backends.cairo(.{
            .render = render,
        }),
        .sample_access = true,
        .targetFps = 60,
    },
};

pub fn plugin() zigplug.Plugin {
    return zigplug.Plugin.new(@This(), .{
        .allocator = gpa.allocator(),
    }, .{
        .init = @ptrCast(&init),
        .deinit = @ptrCast(&deinit),
        .process = @ptrCast(&process),
    });
}

fn init() !*@This() {
    const self = try gpa.allocator().create(@This());
    self.* = .{};
    return self;
}

fn deinit(self: *@This()) void {
    gpa.allocator().destroy(self);
    _ = gpa.deinit();
}

pub fn process(self: *@This(), block: zigplug.ProcessBlock) zigplug.ProcessStatus {
    _ = self; // autofix
    for (block.out, 0..) |buffer, buffer_i| {
        for (buffer.data, 0..) |channel, channel_i| {
            std.mem.copyForwards(f32, channel[0..buffer.samples], block.in[buffer_i].data[channel_i][0..buffer.samples]);
        }
    }
    return .ok;
}

const cairo = @import("cairo_c");

// TODO: properly handle user gui state
var gui_state: struct {
    lock: std.Thread.RwLock = .{},
    level: [2]f32 = .{ 0.0, 0.0 },
} = .{};

// https://www.musicdsp.org/en/latest/Analysis/19-simple-peak-follower.html
const half_life = 0.1;
const very_small_float = 1.0e-30;

fn render(cr: *cairo.cairo_t, render_data: zigplug.gui.RenderData) !void {
    gui_state.lock.lock();
    defer gui_state.lock.unlock();

    const scalar = std.math.pow(
        f32,
        0.5,
        1.0 / (half_life * @as(f32, @floatFromInt(render_data.plugin_data.sample_rate))),
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

    cairo.cairo_rectangle(
        cr,
        @floatFromInt(render_data.x),
        @floatFromInt(render_data.y),
        @floatFromInt(render_data.w),
        @floatFromInt(render_data.h),
    );
    cairo.cairo_clip_preserve(cr);
    cairo.cairo_set_source_rgb(cr, 0, 0, 0);
    cairo.cairo_fill(cr);

    cairo.cairo_rectangle(
        cr,
        @floatFromInt(render_data.x),
        @floatFromInt(render_data.h),
        @floatFromInt(render_data.w / 2),
        -(gui_state.level[0] * @as(f32, @floatFromInt(render_data.h)) - @as(f32, @floatFromInt(render_data.h)) / 6.0),
    );
    if (gui_state.level[0] >= 1)
        cairo.cairo_set_source_rgb(cr, 1, 0, 0)
    else
        cairo.cairo_set_source_rgb(cr, 0, 1, 0);
    cairo.cairo_fill(cr);

    cairo.cairo_rectangle(
        cr,
        @floatFromInt(render_data.w / 2),
        @floatFromInt(render_data.h),
        @floatFromInt(render_data.w / 2),
        -(gui_state.level[1] * @as(f32, @floatFromInt(render_data.h)) - @as(f32, @floatFromInt(render_data.h)) / 6.0),
    );
    if (gui_state.level[0] >= 1)
        cairo.cairo_set_source_rgb(cr, 1, 0, 0)
    else
        cairo.cairo_set_source_rgb(cr, 0, 1, 0);
    cairo.cairo_fill(cr);
}
