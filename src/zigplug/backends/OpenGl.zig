const builtin = @import("builtin");
const std = @import("std");
const options = @import("zigplug_options");
const zigplug = @import("../zigplug.zig");
const gui = @import("../gui.zig");

pub const c = @cImport({
    @cInclude("pugl/pugl.h");
    @cInclude("pugl/gl.h");
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

var data: struct {
    world: ?*c.PuglWorld = null,
    view: ?*c.PuglView = null,
} = undefined;

pub const Callbacks = struct {
    render: fn () anyerror!void,
    create: ?fn (comptime zigplug.Plugin, type) anyerror!void = null,
    destroy: ?fn (comptime zigplug.Plugin, type) anyerror!void = null,
};

pub fn backend(callbacks: Callbacks) gui.Backend {
    const B = struct {
        fn onEvent(view: ?*c.PuglView, event: [*c]const c.PuglEvent) callconv(.C) c.PuglStatus {
            switch (event.*.type) {
                c.PUGL_EXPOSE => {
                    callbacks.render() catch return c.PUGL_REALIZE_FAILED;
                },
                c.PUGL_UPDATE => {
                    return c.puglPostRedisplay(view);
                },
                else => {},
            }

            return c.PUGL_SUCCESS;
        }

        pub fn create(comptime plugin: zigplug.Plugin) PuglError!void {
            data.world = c.puglNewWorld(c.PUGL_MODULE, 0);
            try handleError(c.puglSetWorldString(data.world, c.PUGL_CLASS_NAME, plugin.name));

            data.view = c.puglNewView(data.world);
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

            switch (options.gui_backend) {
                .gl => {
                    try handleError(c.puglSetBackend(data.view, c.puglGlBackend()));
                    try handleError(c.puglSetViewHint(data.view, c.PUGL_CONTEXT_VERSION_MAJOR, 3));
                    try handleError(c.puglSetViewHint(data.view, c.PUGL_CONTEXT_VERSION_MINOR, 3));
                    try handleError(c.puglSetViewHint(data.view, c.PUGL_CONTEXT_PROFILE, c.PUGL_OPENGL_COMPATIBILITY_PROFILE));
                },
                else => unreachable,
            }

            if (callbacks.create) |func| {
                try func(plugin);
            }

            plugin.data.gui_created = true;
        }

        pub fn destroy(comptime plugin: zigplug.Plugin) !void {
            if (callbacks.destroy) |func| {
                try func(plugin);
            }

            c.puglFreeView(data.view);
            c.puglFreeWorld(data.world);

            plugin.data.gui_created = false;
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

        pub fn suggestTitle(comptime plugin: zigplug.Plugin, title: [:0]const u8) !void {
            _ = plugin; // autofix

            try handleError(c.puglSetViewString(data.view, c.PUGL_WINDOW_TITLE, title.ptr));
        }

        pub fn tick(comptime plugin: zigplug.Plugin) !void {
            _ = plugin; // autofix
            try handleError(c.puglUpdate(data.world, 0));
        }
    };

    return .{
        .create = B.create,
        .destroy = B.destroy,
        .setParent = B.setParent,
        .show = B.show,
        .tick = B.tick,
        .suggestTitle = B.suggestTitle,
    };
}
