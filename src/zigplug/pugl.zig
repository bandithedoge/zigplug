const std = @import("std");
const builtin = @import("builtin");

const options = @import("zigplug_options");
const pugl = @import("pugl");

const gui = @import("gui.zig");
const zigplug = @import("zigplug.zig");

const log = std.log.scoped(.Pugl);

// TODO: don't use global variables
var gui_data: struct {
    world: pugl.World = undefined,
    view: pugl.View = undefined,
} = undefined;

pub const Version = enum {
    gl2_2,
    gl3_0,
    gl3_3,
    gles2_0,
};

pub const Callbacks = struct {
    render: switch (options.gui_backend) {
        .gl => fn (gui.RenderData) anyerror!void,
        .cairo => fn (*anyopaque, gui.RenderData) anyerror!void,
        else => unreachable,
    },
    create: ?fn (type) anyerror!void = null,
    destroy: ?fn (type) anyerror!void = null,
};

fn puglBackend(api: enum { gl, cairo }, version: ?Version, callbacks: Callbacks) gui.Backend {
    const B = struct {
        fn onEvent(view: *const pugl.View, event: pugl.event.Event) pugl.Error!void {
            const plugin_data = zigplug.PluginData.cast(view.getHandle().?);
            switch (event) {
                .expose => |e| {
                    var render_data: gui.RenderData = .{
                        .x = e.x,
                        .y = e.y,
                        .w = e.width,
                        .h = e.height,
                        .parameters = plugin_data.parameters.items,
                        .plugin_data = plugin_data,
                    };

                    if (plugin_data.gui) |*gui_d| {
                        if (gui_d.sample_data) |sample_data| {
                            gui_d.sample_lock.lock();
                            defer gui_d.sample_lock.unlock();
                            render_data.process_block = sample_data;
                        }
                    }

                    switch (options.gui_backend) {
                        .gl => callbacks.render(render_data) catch return pugl.Error.RealizeFailed,
                        .cairo => callbacks.render(view.getContext().?, render_data) catch return pugl.Error.RealizeFailed,
                        else => unreachable,
                    }
                },
                else => {},
            }
        }

        pub fn create(comptime Plugin: type, data: *zigplug.PluginData) !void {
            gui_data.world = try .new(.module, .{});
            try gui_data.world.setHint(.class_name, Plugin.desc.name);

            gui_data.view = try .new(&gui_data.world);

            gui_data.view.setHandle(data);

            try gui_data.view.setSizeHint(.default, .{
                .width = Plugin.desc.gui.?.default_width,
                .height = Plugin.desc.gui.?.default_height,
            });
            try gui_data.view.setSizeHint(.minimum, .{
                .width = Plugin.desc.gui.?.min_width orelse Plugin.desc.gui.?.default_width,
                .height = Plugin.desc.gui.?.min_height orelse Plugin.desc.gui.?.default_height,
            });
            if (Plugin.desc.gui.?.keep_aspect) {
                const gcd = std.math.gcd(Plugin.desc.gui.?.default_width, Plugin.desc.gui.?.default_height);
                const w: u16 = Plugin.desc.gui.?.default_width / gcd;
                const h: u16 = Plugin.desc.gui.?.default_height / gcd;
                try gui_data.view.setSizeHint(.fixed_aspect, .{ .width = w, .height = h });
            }

            try gui_data.view.setBoolHint(.resizable, Plugin.desc.gui.?.resizable);
            try gui_data.view.setType(.normal);

            try gui_data.view.setEventFunc(onEvent);

            switch (api) {
                .gl => {
                    const OpenGlBackend = @import("backend_opengl");
                    const backend = OpenGlBackend.new(&gui_data.view);

                    try gui_data.view.setBackend(backend.backend);
                    switch (version.?) {
                        .gl2_2 => {
                            try gui_data.view.setContextApi(.opengl);
                            try gui_data.view.setIntHint(.context_version_major, 2);
                            try gui_data.view.setIntHint(.context_version_minor, 2);
                        },
                        .gl3_0 => {
                            try gui_data.view.setContextApi(.opengl);
                            try gui_data.view.setIntHint(.context_version_major, 3);
                            try gui_data.view.setIntHint(.context_version_minor, 0);
                        },
                        .gl3_3 => {
                            try gui_data.view.setContextApi(.opengl);
                            try gui_data.view.setIntHint(.context_version_major, 3);
                            try gui_data.view.setIntHint(.context_version_minor, 3);
                        },
                        .gles2_0 => {
                            try gui_data.view.setContextApi(.opengl_es);
                            try gui_data.view.setIntHint(.context_version_major, 2);
                            try gui_data.view.setIntHint(.context_version_minor, 0);
                        },
                    }
                    try gui_data.view.setContextProfile(.core);
                },
                .cairo => {
                    const CairoBackend = @import("backend_cairo");
                    const backend = CairoBackend.new();
                    try gui_data.view.setBackend(backend.backend);
                },
            }

            if (callbacks.create) |func| {
                try func(Plugin);
            }

            // HACK: https://github.com/lv2/pugl/issues/98
            try gui_data.view.setPositionHint(.current, .{ .x = 0, .y = 0 });

            data.gui.?.created = true;
        }

        pub fn destroy(comptime plugin: type) !void {
            if (callbacks.destroy) |func| {
                try func(plugin);
            }

            gui_data.view.free();
            gui_data.world.free();

            const data: *zigplug.PluginData = @ptrCast(@alignCast(gui_data.view.getHandle().?));
            data.gui.?.created = false;
        }

        pub fn setParent(comptime plugin: type, handle: gui.WindowHandle) !void {
            _ = plugin; // autofix

            try gui_data.view.setParent(switch (builtin.target.os.tag) {
                .linux => handle.x11,
                else => unreachable,
            });
        }

        pub fn show(comptime plugin: type, visible: bool) !void {
            _ = plugin; // autofix

            if (visible)
                try gui_data.view.show(.raise)
            else
                try gui_data.view.hide();
        }

        pub fn tick(comptime Plugin: type, event: gui.Event) !void {
            log.debug("tick({})", .{event});

            const data: *zigplug.PluginData = @ptrCast(@alignCast(gui_data.view.getHandle().?));
            std.debug.assert(data.gui != null);
            std.debug.assert(data.gui.?.created);

            switch (event) {
                .ParamChanged, .StateChanged => try gui_data.view.obscure(),
                .Idle => if (Plugin.desc.gui.?.targetFps != null) try gui_data.view.obscure(),
                else => {},
            }
            try gui_data.world.update(0);
        }

        pub fn suggestTitle(comptime plugin: type, title: [:0]const u8) !void {
            _ = plugin; // autofix

            try gui_data.view.setStringHint(.window_title, title);
        }

        pub fn setSize(comptime plugin: type, w: u32, h: u32) !void {
            _ = plugin; // autofix

            try gui_data.view.setSizeHint(.current, .{ .width = w, .height = h });
        }

        pub fn getSize(comptime plugin: type) !gui.Size {
            _ = plugin; // autofix

            const size = gui_data.view.getSizeHint(.current);
            return .{ .w = size.width, .h = size.height };
        }
    };

    return .{
        .create = B.create,
        .destroy = B.destroy,
        .setParent = B.setParent,
        .show = B.show,
        .tick = B.tick,
        .suggestTitle = B.suggestTitle,
        .setSize = B.setSize,
        .getSize = B.getSize,
    };
}

pub fn openGlBackend(version: Version, callbacks: Callbacks) gui.Backend {
    if (options.gui_backend != .gl)
        @compileError("OpenGL backend was not selected in build.zig");

    return puglBackend(.gl, version, callbacks);
}

pub fn cairoBackend(callbacks: Callbacks) gui.Backend {
    if (options.gui_backend != .cairo)
        @compileError("Cairo backend was not selected in build.zig");

    return puglBackend(.cairo, null, callbacks);
}
