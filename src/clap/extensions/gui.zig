const std = @import("std");
const builtin = @import("builtin");
const zigplug = @import("zigplug");
const c = @import("clap_c");
const clap = @import("../adapter.zig");

const preferred_api: [:0]u8 = switch (builtin.target.os.tag) {
    .linux => @constCast(&c.CLAP_WINDOW_API_X11),
    else => unreachable,
};

const log = std.log.scoped(.zigplugClapGui);

pub fn Gui(comptime Plugin: type) *const c.clap_plugin_gui_t {
    const gui = struct {
        pub fn is_api_supported(clap_plugin: [*c]const c.clap_plugin_t, api: [*c]const u8, is_floating: bool) callconv(.c) bool {
            _ = clap_plugin; // autofix
            log.info("is_api_supported({s}, {})", .{ api, is_floating });

            return !is_floating and std.mem.eql(u8, std.mem.span(api), preferred_api);
        }

        pub fn get_preferred_api(clap_plugin: [*c]const c.clap_plugin_t, api: [*c][*c]const u8, is_floating: [*c]bool) callconv(.c) bool {
            _ = clap_plugin; // autofix
            log.info("get_preferred_api()", .{});
            api.* = preferred_api;
            is_floating.* = false;
            return true;
        }

        fn requestResize(data_p: *anyopaque, w: u32, h: u32) bool {
            const data: *clap.Data = @ptrCast(@alignCast(data_p));
            return data.host_gui.*.request_resize.?(data.host.?, w, h);
        }

        pub fn create(clap_plugin: [*c]const c.clap_plugin_t, api: [*c]const u8, is_floating: bool) callconv(.c) bool {
            log.info("create({s}, {})", .{ api, is_floating });
            const data = clap.Data.cast(clap_plugin);

            std.debug.assert(std.mem.eql(u8, std.mem.span(api), preferred_api));

            Plugin.desc.gui.?.backend.create(Plugin, &data.plugin_data) catch return false;
            data.plugin_data.gui = .{
                .created = true,
                .visible = false,
                .requestResize = requestResize,
            };

            return true;
        }

        pub fn destroy(clap_plugin: [*c]const c.clap_plugin_t) callconv(.c) void {
            log.info("destroy()", .{});
            const data = clap.Data.cast(clap_plugin);

            std.debug.assert(Plugin.desc.gui != null and data.plugin_data.gui != null);

            Plugin.desc.gui.?.backend.destroy(Plugin) catch {};
            data.plugin_data.gui.?.visible = false;
            data.plugin_data.gui.?.created = false;
        }

        pub fn set_scale(clap_plugin: [*c]const c.clap_plugin_t, scale: f64) callconv(.c) bool {
            _ = clap_plugin; // autofix
            log.info("set_scale({})", .{scale});

            return true;
        }

        pub fn get_size(clap_plugin: [*c]const c.clap_plugin_t, width: [*c]u32, height: [*c]u32) callconv(.c) bool {
            _ = clap_plugin; // autofix
            log.info("get_size()", .{});

            if (Plugin.desc.gui.?.backend.getSize) |getSize| {
                const size = getSize(Plugin) catch return false;
                width.* = size.w;
                height.* = size.h;
            } else {
                width.* = Plugin.desc.gui.?.default_width;
                height.* = Plugin.desc.gui.?.default_height;
            }

            return true;
        }

        pub fn can_resize(clap_plugin: [*c]const c.clap_plugin_t) callconv(.c) bool {
            _ = clap_plugin; // autofix
            log.info("can_resize()", .{});
            return Plugin.desc.gui.?.resizable;
        }

        pub fn get_resize_hints(clap_plugin: [*c]const c.clap_plugin_t, hints: [*c]c.clap_gui_resize_hints_t) callconv(.c) bool {
            _ = hints; // autofix
            _ = clap_plugin; // autofix
            log.info("get_resize_hints()", .{});
            return false;
        }

        pub fn adjust_size(clap_plugin: [*c]const c.clap_plugin_t, width: [*c]u32, height: [*c]u32) callconv(.c) bool {
            log.info("adjust_size()", .{});
            return get_size(clap_plugin, width, height);
        }

        pub fn set_size(clap_plugin: [*c]const c.clap_plugin_t, width: u32, height: u32) callconv(.c) bool {
            _ = clap_plugin; // autofix
            log.info("set_size({}, {})", .{ width, height });

            if (comptime Plugin.desc.gui) |gui| {
                if (gui.backend.setSize) |setSize| {
                    setSize(Plugin, width, height) catch return false;
                }
                gui.backend.tick(Plugin, .SizeChanged) catch return false;
            }

            return true;
        }

        pub fn set_parent(clap_plugin: [*c]const c.clap_plugin_t, window: [*c]const c.clap_window_t) callconv(.c) bool {
            _ = clap_plugin; // autofix
            log.info("set_parent({s})", .{window.*.api});

            std.debug.assert(std.mem.eql(u8, std.mem.span(window.*.api), preferred_api));
            std.debug.assert(Plugin.desc.gui != null);

            const handle: zigplug.gui.WindowHandle = switch (builtin.target.os.tag) {
                .linux => .{ .x11 = window.*.unnamed_0.x11 },
                else => unreachable,
            };

            Plugin.desc.gui.?.backend.setParent(Plugin, handle) catch return false;

            return true;
        }

        pub fn set_transient(clap_plugin: [*c]const c.clap_plugin_t, window: [*c]const c.clap_window_t) callconv(.c) bool {
            _ = window; // autofix
            _ = clap_plugin; // autofix
            log.info("set_transient()", .{});
            return false;
        }

        pub fn suggest_title(clap_plugin: [*c]const c.clap_plugin_t, title: [*c]const u8) callconv(.c) void {
            _ = clap_plugin; // autofix
            log.info("suggest_title({s})", .{title});
            std.debug.assert(Plugin.desc.gui != null);

            if (Plugin.desc.gui.?.backend.suggestTitle) |suggestTitle| {
                suggestTitle(Plugin, std.mem.span(title)) catch {};
            }
        }

        pub fn show(clap_plugin: [*c]const c.clap_plugin_t) callconv(.c) bool {
            log.info("show()", .{});
            const data = clap.Data.cast(clap_plugin);

            std.debug.assert(Plugin.desc.gui != null and data.plugin_data.gui != null);

            Plugin.desc.gui.?.backend.show(Plugin, true) catch return false;
            data.plugin_data.gui.?.visible = true;

            return true;
        }

        pub fn hide(clap_plugin: [*c]const c.clap_plugin_t) callconv(.c) bool {
            log.info("hide()", .{});
            const data = clap.Data.cast(clap_plugin);

            std.debug.assert(Plugin.desc.gui != null and data.plugin_data.gui != null);

            Plugin.desc.gui.?.backend.show(Plugin, false) catch return false;
            data.plugin_data.gui.?.visible = false;

            return true;
        }
    };

    return &.{
        .is_api_supported = gui.is_api_supported,
        .get_preferred_api = gui.get_preferred_api,
        .create = gui.create,
        .destroy = gui.destroy,
        .set_scale = gui.set_scale,
        .get_size = gui.get_size,
        .can_resize = gui.can_resize,
        .get_resize_hints = gui.get_resize_hints,
        .adjust_size = gui.adjust_size,
        .set_size = gui.set_size,
        .set_parent = gui.set_parent,
        .set_transient = gui.set_transient,
        .suggest_title = gui.suggest_title,
        .show = gui.show,
        .hide = gui.hide,
    };
}
