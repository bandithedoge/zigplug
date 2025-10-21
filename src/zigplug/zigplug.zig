const std = @import("std");

pub const parameters = @import("parameters.zig");
pub const Parameter = parameters.Parameter;

pub const log = std.log.scoped(.zigplug);

pub const NoteEvent = struct {
    type: enum { on, off, choke, end },
    /// From C-1 to G9. 60 is middle C, `null` means wildcard
    note: ?u8,
    channel: ?u5,
    timing: u32,
    velocity: f64,
};

pub const ProcessBlock = struct {
    context: *anyopaque,
    fn_nextNoteEvent: *const fn (*anyopaque) ?NoteEvent,

    in: []const []const []const f32 = &.{},
    out: [][][]f32 = &.{},
    samples: usize = 0,
    sample_rate: u32 = 0,

    pub fn nextNoteEvent(self: *const ProcessBlock) ?NoteEvent {
        return self.fn_nextNoteEvent(self.context);
    }
};

pub const ProcessStatus = enum {
    ok,
    failed,
};

pub const PluginData = struct {
    /// Hz
    sample_rate: u32 = 0,
    plugin: Plugin,

    pub fn cast(ptr: ?*anyopaque) *PluginData {
        return @ptrCast(@alignCast(ptr));
    }
};

pub const AudioPorts = struct {
    pub const Port = struct {
        name: [:0]const u8, // TODO: make this optional
        channels: u32,
    };

    in: []const Port,
    out: []const Port,
};

pub const NotePorts = struct {
    pub const Port = struct {
        name: [:0]const u8,
    };

    in: []const Port,
    out: []const Port,
};

pub const Meta = struct {
    name: [:0]const u8,
    vendor: [:0]const u8,
    url: [:0]const u8,
    version: [:0]const u8,
    description: [:0]const u8,
    manual_url: ?[:0]const u8 = null,
    support_url: ?[:0]const u8 = null,

    audio_ports: ?AudioPorts = null,
    note_ports: ?NotePorts = null,

    /// When enabled, the signal is split into smaller buffers of different sizes so that every parameter change is
    /// accounted for. This slightly increases CPU usage and potentially reduces the effectiveness of optimizations like
    /// SIMD in return for more accurate parameter automation.
    ///
    /// Has no effect when the plugin has no parameters
    // TODO: set this for individual parameters
    sample_accurate_automation: bool = false,
};

pub const Plugin = struct {
    context: *anyopaque,

    vtable: struct {
        // TODO: verify types
        deinit: *const fn (*anyopaque) void,
        process: *const fn (*anyopaque, ProcessBlock, ?*const anyopaque) anyerror!void,
    },

    allocator: std.mem.Allocator,
    parameters: ?*anyopaque = null,

    // error unions make `==` type comparison wonky so we have to compare arg and return types manually
    fn validateFunction(comptime Container: type, comptime name: []const u8, comptime args: []const type, Return: type) void {
        const ExpectedType = @Type(.{ .@"fn" = .{
            .params = comptime blk: {
                var params: [args.len]std.builtin.Type.Fn.Param = undefined;
                for (args, 0..) |Arg, i|
                    params[i] = .{
                        .type = Arg,
                        .is_generic = false,
                        .is_noalias = false,
                    };
                break :blk &params;
            },
            .return_type = Return,
            .calling_convention = .auto,
            .is_var_args = false,
            .is_generic = false,
        } });

        if (!@hasDecl(Container, name))
            @compileError("Plugin is missing method '" ++ name ++ "' of type '" ++ @typeName(ExpectedType) ++ "'");

        const Fn = @TypeOf(@field(Container, name));
        const info = @typeInfo(Fn).@"fn";
        const msg = "Wrong signature for method '" ++ name ++ "': expected '" ++ @typeName(ExpectedType) ++ "', found '" ++ @typeName(Fn) ++ "'";

        const Actual = info.return_type orelse void;

        switch (@typeInfo(Actual)) {
            .error_union => |actual_error_union| {
                switch (@typeInfo(Return)) {
                    .error_union => |expected_error_union| {
                        if (actual_error_union.payload != expected_error_union.payload)
                            @compileError(msg);
                    },
                    else => @compileError(msg),
                }
            },
            else => if (Actual != Return) @compileError(msg),
        }

        const params = info.params;
        if (params.len != args.len)
            @compileError(msg);

        inline for (params, args) |param, Arg| {
            if (param.type != Arg)
                @compileError(msg);
        }
    }

    pub fn new(comptime T: type) !Plugin {
        if (!@hasDecl(T, "meta") or @TypeOf(T.meta) != Meta)
            @compileError(
                \\Plugin is missing a metadata object.
                \\
                \\Add one to your root plugin struct:
                \\`pub const meta = @import("zigplug").Meta{...};`
            );

        validateFunction(T, "init", &.{}, anyerror!T);
        validateFunction(T, "deinit", &.{*T}, void);
        validateFunction(T, "allocator", &.{*T}, std.mem.Allocator);

        if (@hasDecl(T, "Parameters")) {
            const Parameters = T.Parameters;
            validateFunction(T, "process", &.{ *T, ProcessBlock, *const Parameters }, anyerror!void);
            switch (@typeInfo(Parameters)) {
                .@"struct" => |info| {
                    inline for (info.fields) |field| {
                        if (field.type != Parameter)
                            @compileError("`Parameters` struct field '" ++ field.name ++ "' is not of type `zigplug.Parameter`");
                        if (field.defaultValue() == null)
                            @compileError("`Parameters` struct field '" ++ field.name ++ "' has no default value");
                    }
                },
                else => @compileError("`Parameters` type is not a struct"),
            }
        } else validateFunction(T, "process", &.{ *T, ProcessBlock }, anyerror!void);

        var plugin = try T.init();
        const allocator = plugin.allocator();

        const context = try allocator.create(T);
        context.* = plugin;
        return .{
            .context = context,
            .vtable = .{
                .deinit = @ptrCast(&T.deinit),
                .process = @ptrCast(&T.process),
            },
            .allocator = context.allocator(),
        };
    }

    pub inline fn deinit(self: *Plugin, comptime P: type) void {
        self.vtable.deinit(self.context);

        const plugin: *P = @ptrCast(@alignCast(self.context));
        self.allocator.destroy(plugin);
    }

    pub inline fn process(self: *Plugin, block: ProcessBlock, params: ?*const anyopaque) !void {
        try self.vtable.process(self.context, block, params);
    }
};

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
