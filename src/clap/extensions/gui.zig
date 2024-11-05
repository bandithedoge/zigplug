const std = @import("std");
const zigplug = @import("zigplug");
const clap = @import("c");

const x = @cImport(@cInclude("X11/Xatom.h"));

pub fn Gui(comptime plugin: zigplug.Plugin) type {
    _ = plugin; // autofix
    return extern struct {
        pub fn is_api_supported(clap_plugin: [*c]const clap.clap_plugin_t, api: [*c]const u8, is_floating: bool) callconv(.C) bool {
            _ = clap_plugin; // autofix
            return !is_floating and std.mem.eql(u8, std.mem.span(api), &clap.CLAP_WINDOW_API_X11);
        }

        pub fn get_preferred_api(clap_plugin: [*c]const clap.clap_plugin_t, api: [*c][*c]const u8, is_floating: [*c]bool) callconv(.C) bool {
            _ = clap_plugin; // autofix
            api.* = &clap.CLAP_WINDOW_API_X11;
            is_floating.* = false;
            return true;
        }

        pub fn create(clap_plugin: [*c]const clap.clap_plugin_t, api: [*c]const u8, is_floating: bool) callconv(.C) bool {
            _ = is_floating; // autofix
            _ = api; // autofix
            _ = clap_plugin; // autofix

            return true;
        }

        pub fn destroy(clap_plugin: [*c]const clap.clap_plugin_t) callconv(.C) void {
            _ = clap_plugin; // autofix
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
            return false;
        }

        pub fn get_resize_hints(clap_plugin: [*c]const clap.clap_plugin_t, hints: [*c]clap.clap_gui_resize_hints_t) callconv(.C) bool {
            _ = hints; // autofix
            _ = clap_plugin; // autofix
            return true;
        }

        pub fn adjust_size(clap_plugin: [*c]const clap.clap_plugin_t, width: [*c]u32, height: [*c]u32) callconv(.C) bool {
            _ = height; // autofix
            _ = width; // autofix
            _ = clap_plugin; // autofix
            return true;
        }

        pub fn set_size(clap_plugin: [*c]const clap.clap_plugin_t, width: u32, height: u32) callconv(.C) bool {
            _ = height; // autofix
            _ = width; // autofix
            _ = clap_plugin; // autofix
            return true;
        }

        pub fn set_parent(clap_plugin: [*c]const clap.clap_plugin_t, window: [*c]const clap.clap_window_t) callconv(.C) bool {
            _ = window; // autofix
            _ = clap_plugin; // autofix
            return true;
        }

        pub fn set_transient(clap_plugin: [*c]const clap.clap_plugin_t, window: [*c]const clap.clap_window_t) callconv(.C) bool {
            _ = window; // autofix
            _ = clap_plugin; // autofix
            return true;
        }

        pub fn suggest_title(clap_plugin: [*c]const clap.clap_plugin_t, title: [*c]const u8) callconv(.C) void {
            _ = title; // autofix
            _ = clap_plugin; // autofix
        }

        pub fn show(clap_plugin: [*c]const clap.clap_plugin_t) callconv(.C) bool {
            _ = clap_plugin; // autofix
            return true;
        }

        pub fn hide(clap_plugin: [*c]const clap.clap_plugin_t) callconv(.C) bool {
            _ = clap_plugin; // autofix
            return true;
        }
    };
}
