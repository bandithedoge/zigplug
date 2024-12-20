const builtin = @import("builtin");
const std = @import("std");
const options = @import("zigplug_options");
const zigplug = @import("zigplug.zig");
const gui = @import("gui.zig");

const log = std.log.scoped(.Pugl);

pub const c = @cImport({
    @cInclude("pugl/pugl.h");
    switch (options.gui_backend) {
        .gl => @cInclude("pugl/gl.h"),
        .cairo => {
            @cInclude("pugl/cairo.h");
            @cInclude("cairo/cairo.h");
        },
        else => unreachable,
    }
});

const PuglError = error{
    Unknown,
    BadBackend,
    BadConfiguration,
    BadParameter,
    BackendFailed,
    RegistrationFailed,
    RealizeFailed,
    SetFormatFailed,
    CreateContextFailed,
    Unsupported,
    NoMemory,
};

fn handleError(status: c.PuglStatus) PuglError!void {
    if (status != 0) {
        zigplug.log.err("pugl error: {s}", .{c.puglStrerror(status)});
    }

    switch (status) {
        c.PUGL_UNKNOWN_ERROR => return PuglError.Unknown,
        c.PUGL_BAD_BACKEND => return PuglError.BadBackend,
        c.PUGL_BAD_CONFIGURATION => return PuglError.BadConfiguration,
        c.PUGL_BAD_PARAMETER => return PuglError.BadParameter,
        c.PUGL_BACKEND_FAILED => return PuglError.BackendFailed,
        c.PUGL_REGISTRATION_FAILED => return PuglError.RegistrationFailed,
        c.PUGL_REALIZE_FAILED => return PuglError.RealizeFailed,
        c.PUGL_SET_FORMAT_FAILED => return PuglError.SetFormatFailed,
        c.PUGL_CREATE_CONTEXT_FAILED => return PuglError.CreateContextFailed,
        c.PUGL_UNSUPPORTED => return PuglError.Unsupported,
        c.PUGL_NO_MEMORY => return PuglError.NoMemory,

        else => {},
    }
}

// TODO: don't use global variables
var data: struct {
    world: ?*c.PuglWorld = null,
    view: ?*c.PuglView = null,
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
        .cairo => fn (*c.cairo_t, gui.RenderData) anyerror!void,
        else => unreachable,
    },
    create: ?fn (comptime zigplug.Plugin, type) anyerror!void = null,
    destroy: ?fn (comptime zigplug.Plugin, type) anyerror!void = null,
};

fn puglBackend(api: enum { gl, cairo }, version: ?Version, callbacks: Callbacks) gui.Backend {
    const B = struct {
        fn onEvent(view: ?*c.PuglView, event: [*c]const c.PuglEvent) callconv(.C) c.PuglStatus {
            switch (event.*.type) {
                c.PUGL_EXPOSE => {
                    const plugin_data = zigplug.PluginData.cast(c.puglGetHandle(view));
                    var render_data: gui.RenderData = .{
                        .x = @intCast(event.*.expose.x),
                        .y = @intCast(event.*.expose.y),
                        .w = event.*.expose.width,
                        .h = event.*.expose.height,
                    };

                    if (plugin_data.gui) |*gui_data| {
                        if (gui_data.sample_data) |sample_data| {
                            gui_data.sample_lock.lock();
                            defer gui_data.sample_lock.unlock();
                            render_data.process_block = sample_data;
                        }
                    }

                    // HACK: https://github.com/lv2/pugl/issues/98
                    _ = c.puglSetPosition(data.view, 0, 0);

                    switch (options.gui_backend) {
                        .gl => callbacks.render(render_data) catch return c.PUGL_REALIZE_FAILED,
                        .cairo => callbacks.render(@ptrCast(c.puglGetContext(data.view)), render_data) catch return c.PUGL_REALIZE_FAILED,
                        else => unreachable,
                    }
                },
                // c.PUGL_UPDATE => {
                //     _ = c.puglPostRedisplay(view);
                // },
                else => {},
            }

            return c.PUGL_SUCCESS;
        }

        pub fn create(comptime plugin: zigplug.Plugin) !void {
            data.world = c.puglNewWorld(c.PUGL_MODULE, 0);
            try handleError(c.puglSetWorldString(data.world, c.PUGL_CLASS_NAME, plugin.name));

            data.view = c.puglNewView(data.world);

            c.puglSetHandle(data.view, plugin.data);

            try handleError(c.puglSetSizeHint(
                data.view,
                c.PUGL_DEFAULT_SIZE,
                plugin.gui.?.default_width,
                plugin.gui.?.default_height,
            ));
            try handleError(c.puglSetSizeHint(
                data.view,
                c.PUGL_MIN_SIZE,
                plugin.gui.?.min_width orelse plugin.gui.?.default_width,
                plugin.gui.?.min_height orelse plugin.gui.?.default_height,
            ));
            if (plugin.gui.?.keep_aspect) {
                const gcd = std.math.gcd(plugin.gui.?.default_width, plugin.gui.?.default_height);
                const w: u16 = plugin.gui.?.default_width / gcd;
                const h: u16 = plugin.gui.?.default_height / gcd;
                try handleError(c.puglSetSizeHint(data.view, c.PUGL_FIXED_ASPECT, w, h));
            }
            try handleError(c.puglSetViewHint(data.view, c.PUGL_RESIZABLE, if (plugin.gui.?.resizable) c.PUGL_TRUE else c.PUGL_FALSE));
            try handleError(c.puglSetViewHint(data.view, c.PUGL_VIEW_TYPE, c.PUGL_VIEW_TYPE_NORMAL));

            try handleError(c.puglSetEventFunc(data.view, onEvent));

            switch (api) {
                .gl => {
                    try handleError(c.puglSetBackend(data.view, c.puglGlBackend()));
                    switch (version.?) {
                        .gl2_2 => {
                            try handleError(c.puglSetViewHint(data.view, c.PUGL_CONTEXT_API, c.PUGL_OPENGL_API));
                            try handleError(c.puglSetViewHint(data.view, c.PUGL_CONTEXT_VERSION_MAJOR, 2));
                            try handleError(c.puglSetViewHint(data.view, c.PUGL_CONTEXT_VERSION_MINOR, 2));
                        },
                        .gl3_0 => {
                            try handleError(c.puglSetViewHint(data.view, c.PUGL_CONTEXT_API, c.PUGL_OPENGL_API));
                            try handleError(c.puglSetViewHint(data.view, c.PUGL_CONTEXT_VERSION_MAJOR, 3));
                            try handleError(c.puglSetViewHint(data.view, c.PUGL_CONTEXT_VERSION_MINOR, 0));
                        },
                        .gl3_3 => {
                            try handleError(c.puglSetViewHint(data.view, c.PUGL_CONTEXT_API, c.PUGL_OPENGL_API));
                            try handleError(c.puglSetViewHint(data.view, c.PUGL_CONTEXT_VERSION_MAJOR, 3));
                            try handleError(c.puglSetViewHint(data.view, c.PUGL_CONTEXT_VERSION_MINOR, 3));
                        },
                        .gles2_0 => {
                            try handleError(c.puglSetViewHint(data.view, c.PUGL_CONTEXT_API, c.PUGL_OPENGL_ES_API));
                            try handleError(c.puglSetViewHint(data.view, c.PUGL_CONTEXT_VERSION_MAJOR, 2));
                            try handleError(c.puglSetViewHint(data.view, c.PUGL_CONTEXT_VERSION_MINOR, 0));
                        },
                    }
                    try handleError(c.puglSetViewHint(data.view, c.PUGL_CONTEXT_PROFILE, c.PUGL_OPENGL_CORE_PROFILE));
                },
                .cairo => {
                    try handleError(c.puglSetBackend(data.view, c.puglCairoBackend()));
                },
            }

            if (callbacks.create) |func| {
                try func(plugin);
            }

            // plugin.data.gui_created = true;
        }

        pub fn destroy(comptime plugin: zigplug.Plugin) !void {
            if (callbacks.destroy) |func| {
                try func(plugin);
            }

            c.puglFreeView(data.view);
            c.puglFreeWorld(data.world);

            // plugin.data.gui_created = false;
        }

        pub fn setParent(comptime plugin: zigplug.Plugin, handle: gui.WindowHandle) !void {
            _ = plugin; // autofix

            try handleError(c.puglSetParentWindow(data.view, switch (builtin.target.os.tag) {
                .linux => handle.x11,
                else => unreachable,
            }));
        }

        pub fn show(comptime plugin: zigplug.Plugin, visible: bool) !void {
            _ = plugin; // autofix

            if (visible) {
                try handleError(c.puglShow(data.view, c.PUGL_SHOW_RAISE));
            } else {
                try handleError(c.puglHide(data.view));
            }
        }

        pub fn tick(comptime plugin: zigplug.Plugin, event: gui.Event) !void {
            _ = plugin; // autofix
            log.debug("tick({})", .{event});

            switch (event) {
                .ParamChanged,
                .StateChanged,
                => try handleError(c.puglPostRedisplay(data.view)),
                else => {},
            }
            try handleError(c.puglUpdate(data.world, 0));
        }

        pub fn suggestTitle(comptime plugin: zigplug.Plugin, title: [:0]const u8) !void {
            _ = plugin; // autofix

            try handleError(c.puglSetViewString(data.view, c.PUGL_WINDOW_TITLE, title.ptr));
        }

        pub fn setSize(comptime plugin: zigplug.Plugin, w: u32, h: u32) !void {
            _ = plugin; // autofix

            try handleError(c.puglSetSize(data.view, w, h));
        }

        pub fn getSize(comptime plugin: zigplug.Plugin) !gui.Size {
            _ = plugin; // autofix

            var w: c_int = undefined;
            var h: c_int = undefined;
            c.puglGetSize(data.view, &w, &h);
            return .{ .w = @intCast(w), .h = @intCast(h) };
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

pub fn openGl(version: Version, callbacks: Callbacks) gui.Backend {
    if (options.gui_backend != .gl)
        @compileError("OpenGL backend was not selected in build.zig");

    return puglBackend(.gl, version, callbacks);
}

pub fn cairo(callbacks: Callbacks) gui.Backend {
    if (options.gui_backend != .cairo)
        @compileError("Cairo backend was not selected in build.zig");

    return puglBackend(.cairo, null, callbacks);
}
