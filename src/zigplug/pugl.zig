const builtin = @import("builtin");
const std = @import("std");
const options = @import("zigplug_options");
const zigplug = @import("zigplug.zig");
const gui = @import("gui.zig");

const log = std.log.scoped(.Pugl);

pub const c = @cImport({
    @cDefine("PUGL_STATIC", {});
    @cInclude("pugl/pugl.h");
    switch (options.gui_backend) {
        .gl => @cInclude("pugl/gl.h"),
        .cairo => {
            @cInclude("pugl/cairo.h");
            @cInclude("cairo.h");
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
var gui_data: struct {
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
    create: ?fn (type) anyerror!void = null,
    destroy: ?fn (type) anyerror!void = null,
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
                        .parameters = plugin_data.parameters.items,
                        .plugin_data = plugin_data,
                    };

                    if (plugin_data.gui) |*gui_d| {
                        if (plugin_data.gui.?.sample_data) |sample_data| {
                            gui_d.sample_lock.lock();
                            defer gui_d.sample_lock.unlock();
                            render_data.process_block = sample_data;
                        }
                    }

                    switch (options.gui_backend) {
                        .gl => callbacks.render(render_data) catch return c.PUGL_REALIZE_FAILED,
                        .cairo => callbacks.render(@ptrCast(c.puglGetContext(gui_data.view)), render_data) catch return c.PUGL_REALIZE_FAILED,
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

        pub fn create(comptime Plugin: type, data: *zigplug.PluginData) !void {
            gui_data.world = c.puglNewWorld(c.PUGL_MODULE, 0);
            try handleError(c.puglSetWorldString(gui_data.world, c.PUGL_CLASS_NAME, Plugin.desc.name));

            gui_data.view = c.puglNewView(gui_data.world);

            c.puglSetHandle(gui_data.view, data);

            try handleError(c.puglSetSizeHint(
                gui_data.view,
                c.PUGL_DEFAULT_SIZE,
                Plugin.desc.gui.?.default_width,
                Plugin.desc.gui.?.default_height,
            ));
            try handleError(c.puglSetSizeHint(
                gui_data.view,
                c.PUGL_MIN_SIZE,
                Plugin.desc.gui.?.min_width orelse Plugin.desc.gui.?.default_width,
                Plugin.desc.gui.?.min_height orelse Plugin.desc.gui.?.default_height,
            ));
            if (Plugin.desc.gui.?.keep_aspect) {
                const gcd = std.math.gcd(Plugin.desc.gui.?.default_width, Plugin.desc.gui.?.default_height);
                const w: u16 = Plugin.desc.gui.?.default_width / gcd;
                const h: u16 = Plugin.desc.gui.?.default_height / gcd;
                try handleError(c.puglSetSizeHint(gui_data.view, c.PUGL_FIXED_ASPECT, w, h));
            }
            try handleError(c.puglSetViewHint(gui_data.view, c.PUGL_RESIZABLE, if (Plugin.desc.gui.?.resizable) c.PUGL_TRUE else c.PUGL_FALSE));
            try handleError(c.puglSetViewHint(gui_data.view, c.PUGL_VIEW_TYPE, c.PUGL_VIEW_TYPE_NORMAL));

            try handleError(c.puglSetEventFunc(gui_data.view, onEvent));

            switch (api) {
                .gl => {
                    try handleError(c.puglSetBackend(gui_data.view, c.puglGlBackend()));
                    switch (version.?) {
                        .gl2_2 => {
                            try handleError(c.puglSetViewHint(gui_data.view, c.PUGL_CONTEXT_API, c.PUGL_OPENGL_API));
                            try handleError(c.puglSetViewHint(gui_data.view, c.PUGL_CONTEXT_VERSION_MAJOR, 2));
                            try handleError(c.puglSetViewHint(gui_data.view, c.PUGL_CONTEXT_VERSION_MINOR, 2));
                        },
                        .gl3_0 => {
                            try handleError(c.puglSetViewHint(gui_data.view, c.PUGL_CONTEXT_API, c.PUGL_OPENGL_API));
                            try handleError(c.puglSetViewHint(gui_data.view, c.PUGL_CONTEXT_VERSION_MAJOR, 3));
                            try handleError(c.puglSetViewHint(gui_data.view, c.PUGL_CONTEXT_VERSION_MINOR, 0));
                        },
                        .gl3_3 => {
                            try handleError(c.puglSetViewHint(gui_data.view, c.PUGL_CONTEXT_API, c.PUGL_OPENGL_API));
                            try handleError(c.puglSetViewHint(gui_data.view, c.PUGL_CONTEXT_VERSION_MAJOR, 3));
                            try handleError(c.puglSetViewHint(gui_data.view, c.PUGL_CONTEXT_VERSION_MINOR, 3));
                        },
                        .gles2_0 => {
                            try handleError(c.puglSetViewHint(gui_data.view, c.PUGL_CONTEXT_API, c.PUGL_OPENGL_ES_API));
                            try handleError(c.puglSetViewHint(gui_data.view, c.PUGL_CONTEXT_VERSION_MAJOR, 2));
                            try handleError(c.puglSetViewHint(gui_data.view, c.PUGL_CONTEXT_VERSION_MINOR, 0));
                        },
                    }
                    try handleError(c.puglSetViewHint(gui_data.view, c.PUGL_CONTEXT_PROFILE, c.PUGL_OPENGL_CORE_PROFILE));
                },
                .cairo => {
                    try handleError(c.puglSetBackend(gui_data.view, c.puglCairoBackend()));
                },
            }

            if (callbacks.create) |func| {
                try func(Plugin);
            }

            // HACK: https://github.com/lv2/pugl/issues/98
            _ = c.puglSetPosition(gui_data.view, 0, 0);

            // plugin.data.gui_created = true;
        }

        pub fn destroy(comptime plugin: type) !void {
            if (callbacks.destroy) |func| {
                try func(plugin);
            }

            c.puglFreeView(gui_data.view);
            c.puglFreeWorld(gui_data.world);

            // plugin.data.gui_created = false;
        }

        pub fn setParent(comptime plugin: type, handle: gui.WindowHandle) !void {
            _ = plugin; // autofix

            try handleError(c.puglSetParentWindow(gui_data.view, switch (builtin.target.os.tag) {
                .linux => handle.x11,
                else => unreachable,
            }));
        }

        pub fn show(comptime plugin: type, visible: bool) !void {
            _ = plugin; // autofix

            if (visible) {
                try handleError(c.puglShow(gui_data.view, c.PUGL_SHOW_RAISE));
            } else {
                try handleError(c.puglHide(gui_data.view));
            }
        }

        pub fn tick(comptime plugin: type, event: gui.Event) !void {
            _ = plugin; // autofix
            log.debug("tick({})", .{event});

            switch (event) {
                .ParamChanged,
                .StateChanged,
                => try handleError(c.puglPostRedisplay(gui_data.view)),
                else => {},
            }
            try handleError(c.puglUpdate(gui_data.world, 0));
        }

        pub fn suggestTitle(comptime plugin: type, title: [:0]const u8) !void {
            _ = plugin; // autofix

            try handleError(c.puglSetViewString(gui_data.view, c.PUGL_WINDOW_TITLE, title.ptr));
        }

        pub fn setSize(comptime plugin: type, w: u32, h: u32) !void {
            _ = plugin; // autofix

            try handleError(c.puglSetSize(gui_data.view, w, h));
        }

        pub fn getSize(comptime plugin: type) !gui.Size {
            _ = plugin; // autofix

            var w: c_int = undefined;
            var h: c_int = undefined;
            c.puglGetSize(gui_data.view, &w, &h);
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
