const std = @import("std");
const zigplug = @import("zigplug");

phase: f32,

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

const Parameters =
    enum {
    red,
    green,
    blue,

    pub fn setup(self: @This()) zigplug.parameters.Parameter {
        return switch (self) {
            .red => zigplug.parameters.makeParam(.{ .float = 0.0 }, .{
                .name = "Red",
            }),
            .green => zigplug.parameters.makeParam(.{ .float = 0.0 }, .{
                .name = "Green",
            }),
            .blue => zigplug.parameters.makeParam(.{ .float = 0.0 }, .{
                .name = "Blue",
            }),
        };
    }
};

pub const desc: zigplug.Description = .{
    .id = "com.bandithedoge.zigplug",
    .name = "zigplug cairo",
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

    .Parameters = Parameters,

    .gui = .{
        .backend = zigplug.gui.backends.cairo(.{
            .render = render,
        }),
        .resizable = true,
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
    // gpa.init();
    const self = try gpa.allocator().create(@This());
    self.* = .{ .phase = 0.0 };
    return self;
}

fn deinit(self: *@This()) void {
    gpa.allocator().destroy(self);
    _ = gpa.deinit();
}

fn process(self: *@This(), block: zigplug.ProcessBlock) zigplug.ProcessStatus {
    for (block.out) |buffer| {
        for (buffer.data) |channel| {
            for (0..buffer.samples) |i| {
                channel[i] = @sin(2 * std.math.pi * 440 * self.phase / @as(f32, @floatFromInt(block.sample_rate)));
                self.phase += 1;
            }
        }
    }
    return .ok;
}

const cairo = @import("cairo_c");

fn render(cr: *cairo.cairo_t, render_data: zigplug.gui.RenderData) !void {
    cairo.cairo_rectangle(
        cr,
        @floatFromInt(render_data.x),
        @floatFromInt(render_data.y),
        @floatFromInt(render_data.w),
        @floatFromInt(render_data.h),
    );
    cairo.cairo_clip_preserve(cr);
    cairo.cairo_set_source_rgb(
        cr,
        render_data.getParam(Parameters.red).float,
        render_data.getParam(Parameters.green).float,
        render_data.getParam(Parameters.blue).float,
    );
    cairo.cairo_fill(cr);

    const label = "zigplug sucks";
    var extents: cairo.cairo_text_extents_t = undefined;
    cairo.cairo_set_font_size(cr, 32);
    cairo.cairo_text_extents(cr, label, &extents);
    cairo.cairo_move_to(
        cr,
        @as(f64, @floatFromInt(render_data.w / 2)) - extents.width / 2.0,
        @as(f64, @floatFromInt(render_data.h / 2)) - extents.height / 2.0,
    );
    cairo.cairo_set_source_rgba(cr, 0, 0, 0, 1);
    cairo.cairo_show_text(cr, label);
}
