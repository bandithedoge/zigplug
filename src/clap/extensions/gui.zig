const std = @import("std");
const builtin = @import("builtin");
const zigplug = @import("zigplug");
const clap = @import("c");
const adapter = @import("clap_adapter");

const preferred_api: [:0]u8 = switch (builtin.target.os.tag) {
    .linux => @constCast(&clap.CLAP_WINDOW_API_X11),
    else => unreachable,
};

pub fn Gui(comptime plugin: zigplug.Plugin) type {
    return extern struct {
        pub fn is_api_supported(clap_plugin: [*c]const clap.clap_plugin_t, api: [*c]const u8, is_floating: bool) callconv(.C) bool {
            _ = clap_plugin; // autofix
            return !is_floating and std.mem.eql(u8, std.mem.span(api), preferred_api);
        }

        pub fn get_preferred_api(clap_plugin: [*c]const clap.clap_plugin_t, api: [*c][*c]const u8, is_floating: [*c]bool) callconv(.C) bool {
            _ = clap_plugin; // autofix
            api.* = preferred_api;
            is_floating.* = false;
            return true;
        }

        pub fn create(clap_plugin: [*c]const clap.clap_plugin_t, api: [*c]const u8, is_floating: bool) callconv(.C) bool {
            _ = is_floating; // autofix
            _ = clap_plugin; // autofix

            std.debug.assert(std.mem.eql(u8, std.mem.span(api), preferred_api));

            plugin.gui.?.backend.create(plugin) catch return false;

            plugin.data.gui_created = true;

            return true;
        }

        pub fn destroy(clap_plugin: [*c]const clap.clap_plugin_t) callconv(.C) void {
            _ = clap_plugin; // autofix

            plugin.gui.?.backend.destroy(plugin) catch {};

            plugin.data.gui_created = false;
        }

        pub fn set_scale(clap_plugin: [*c]const clap.clap_plugin_t, scale: f64) callconv(.C) bool {
            _ = scale; // autofix
            _ = clap_plugin; // autofix

            return true;
        }

        pub fn get_size(clap_plugin: [*c]const clap.clap_plugin_t, width: [*c]u32, height: [*c]u32) callconv(.C) bool {
            _ = height; // autofix
            _ = width; // autofix
            _ = clap_plugin; // autofix

            return true;
        }

        pub fn can_resize(clap_plugin: [*c]const clap.clap_plugin_t) callconv(.C) bool {
            _ = clap_plugin; // autofix
            return plugin.gui.?.resizable;
        }

        pub fn get_resize_hints(clap_plugin: [*c]const clap.clap_plugin_t, hints: [*c]clap.clap_gui_resize_hints_t) callconv(.C) bool {
            _ = hints; // autofix
            _ = clap_plugin; // autofix
            return false;
        }

        pub fn adjust_size(clap_plugin: [*c]const clap.clap_plugin_t, width: [*c]u32, height: [*c]u32) callconv(.C) bool {
            return get_size(clap_plugin, width, height);
        }

        pub fn set_size(clap_plugin: [*c]const clap.clap_plugin_t, width: u32, height: u32) callconv(.C) bool {
            _ = height; // autofix
            _ = width; // autofix
            _ = clap_plugin; // autofix
            return true;
        }

        pub fn set_parent(clap_plugin: [*c]const clap.clap_plugin_t, window: [*c]const clap.clap_window_t) callconv(.C) bool {
            _ = clap_plugin; // autofix

            std.debug.assert(std.mem.eql(u8, std.mem.span(window.*.api), preferred_api));

            const handle: zigplug.gui.WindowHandle = switch (builtin.target.os.tag) {
                .linux => .{ .x11 = window.*.unnamed_0.x11 },
                else => unreachable,
            };

            plugin.gui.?.backend.setParent(plugin, handle) catch return false;

            return true;
        }

        pub fn set_transient(clap_plugin: [*c]const clap.clap_plugin_t, window: [*c]const clap.clap_window_t) callconv(.C) bool {
            _ = window; // autofix
            _ = clap_plugin; // autofix
            return false;
        }

        pub fn suggest_title(clap_plugin: [*c]const clap.clap_plugin_t, title: [*c]const u8) callconv(.C) void {
            _ = clap_plugin; // autofix

            if (plugin.gui.?.backend.suggestTitle) |suggestTitle| {
                suggestTitle(plugin, std.mem.span(title)) catch {};
            }
        }

        pub fn show(clap_plugin: [*c]const clap.clap_plugin_t) callconv(.C) bool {
            _ = clap_plugin; // autofix

            plugin.gui.?.backend.show(plugin, true) catch return false;

            return true;
        }

        pub fn hide(clap_plugin: [*c]const clap.clap_plugin_t) callconv(.C) bool {
            _ = clap_plugin; // autofix

            plugin.gui.?.backend.show(plugin, false) catch return false;

            return true;
        }
    };
}
