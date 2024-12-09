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
        .backend = zigplug.gui.backends.openGl(.gles2_0, .{
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
    _ = plug; // autofix
    for (block.out, 0..) |buffer, buffer_i| {
        for (buffer.data, 0..) |channel, channel_i| {
            std.mem.copyForwards(f32, channel[0..buffer.samples], block.in[buffer_i].data[channel_i][0..buffer.samples]);
        }
    }
    return .ok;
}

const gl = zigplug.gui.pugl.c;

fn render(_: zigplug.gui.RenderData) !void {
    // TODO: write a better opengl example (spinning cube?)
    gl.glClearColor(plugin.getParam(.red).float, plugin.getParam(.green).float, plugin.getParam(.blue).float, 0);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);
}
