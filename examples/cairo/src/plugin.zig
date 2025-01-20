const std = @import("std");
const zigplug = @import("zigplug");

phase: f32 = 0.0,

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

    .allocator = gpa.allocator(),
};

pub fn init() @This() {
    // gpa.init();

    return .{};
}

pub fn deinit(self: *@This()) void {
    _ = self; // autofix

    gpa.deinit();
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

fn render(cr: *zigplug.gui.pugl.c.cairo_t, render_data: zigplug.gui.RenderData) !void {
    const c = zigplug.gui.pugl.c;

    c.cairo_rectangle(
        cr,
        @floatFromInt(render_data.x),
        @floatFromInt(render_data.y),
        @floatFromInt(render_data.w),
        @floatFromInt(render_data.h),
    );
    c.cairo_clip_preserve(cr);
    c.cairo_set_source_rgb(
        cr,
        render_data.getParam(Parameters.red).float,
        render_data.getParam(Parameters.green).float,
        render_data.getParam(Parameters.blue).float,
    );
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
