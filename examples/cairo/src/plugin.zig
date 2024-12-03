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
    },

    .gui = .{
        .backend = zigplug.gui.backends.Cairo.backend(.{
            .render = render,
        }),
        .resizable = true,
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
    _ = plug; // autofix
    for (block.out, 0..) |buffer, buffer_i| {
        for (buffer.data, 0..) |channel, channel_i| {
            std.mem.copyForwards(f32, channel[0..buffer.samples], block.in[buffer_i].data[channel_i][0..buffer.samples]);
        }
    }
    return .ok;
}

const c = zigplug.gui.backends.Cairo.c;

fn render(cr: *c.cairo_t, render_data: zigplug.gui.RenderData) !void {
    std.debug.print("chuj\n", .{});
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
        plugin.getParam(.red).float,
        plugin.getParam(.green).float,
        plugin.getParam(.blue).float,
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
