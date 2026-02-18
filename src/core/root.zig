const std = @import("std");

pub const parameters = @import("parameters.zig");
pub const Parameter = parameters.Parameter;

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
    sample_rate_hz: u32 = 0,

    pub fn nextNoteEvent(self: *const ProcessBlock) ?NoteEvent {
        return self.fn_nextNoteEvent(self.context);
    }
};

pub const ProcessStatus = enum {
    ok,
    failed,
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
    pub const Log = struct {
        pub const LogFn = *const fn (
            context: *anyopaque,
            level: std.log.Level,
            text: [:0]const u8,
        ) void;

        context: *anyopaque,
        logFn: LogFn = default,
        allocator: std.mem.Allocator,

        pub fn default(_: *anyopaque, level: std.log.Level, text: [:0]const u8) void {
            switch (level) {
                .err => std.log.err("{s}", .{text}),
                .warn => std.log.warn("{s}", .{text}),
                .info => std.log.info("{s}", .{text}),
                .debug => std.log.debug("{s}", .{text}),
            }
        }

        const stack_size = 512;

        pub inline fn log(self: *const Log, comptime level: std.log.Level, comptime format: []const u8, args: anytype) void {
            if (comptime std.log.defaultLogEnabled(level)) {
                var stack_allocator = std.heap.stackFallback(stack_size, self.allocator);
                const allocator = stack_allocator.get();
                const text = std.fmt.allocPrintSentinel(allocator, format, args, 0) catch return;
                defer allocator.free(text);
                self.logFn(self.context, level, text);
            }
        }

        pub inline fn debug(self: *const Log, comptime format: []const u8, args: anytype) void {
            self.log(.debug, format, args);
        }

        pub inline fn err(self: *const Log, comptime format: []const u8, args: anytype) void {
            self.log(.err, format, args);
        }

        pub inline fn info(self: *const Log, comptime format: []const u8, args: anytype) void {
            self.log(.info, format, args);
        }

        pub inline fn warn(self: *const Log, comptime format: []const u8, args: anytype) void {
            self.log(.warn, format, args);
        }
    };

    context: *anyopaque,
    vtable: struct {
        deinit: *const fn (*anyopaque) void,
        process: *const fn (*anyopaque, ProcessBlock, ?*const anyopaque) anyerror!void,
    },

    allocator: std.mem.Allocator,
    log: *Log,
    parameters: ?parameters.State,
    sample_rate_hz: u32 = 0,

    pub fn init(comptime T: type) !Plugin {
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
        validateFunction(
            T,
            "process",
            if (@hasDecl(T, "Parameters"))
                &.{ *T, ProcessBlock, *const T.Parameters }
            else
                &.{ *T, ProcessBlock },
            anyerror!void,
        );

        const context = try std.heap.page_allocator.create(T);
        context.* = try T.init();

        const allocator = context.allocator();

        const log = try allocator.create(Log);
        log.* = .{
            // SAFETY: only accessed when logFn is different than defaultLog
            .context = undefined,
            .allocator = allocator,
        };

        return .{
            .context = context,
            .vtable = .{
                .deinit = @ptrCast(&T.deinit),
                .process = @ptrCast(&T.process),
            },
            .allocator = allocator,
            .log = log,
            .parameters = if (@hasDecl(T, "Parameters")) blk: {
                const Parameters = T.Parameters;
                switch (@typeInfo(Parameters)) {
                    .@"struct" => |info| {
                        inline for (info.fields) |field| {
                            if (field.type != Parameter)
                                @compileError("`Parameters` struct field '" ++ field.name ++ "' is not of type `zigplug.Parameter`");
                            if (field.defaultValue() == null)
                                @compileError("`Parameters` struct field '" ++ field.name ++ "' has no default value");
                        }
                    },
                    else => @compileError("`Parameters` is not a struct"),
                }

                const parameters_context = try allocator.create(Parameters);
                parameters_context.* = .{};
                const fields = @typeInfo(Parameters).@"struct".fields;

                var parameters_slice = try allocator.alloc(*Parameter, fields.len);

                inline for (fields, 0..) |field, i| {
                    const param = &@field(parameters_context, field.name);
                    switch (param.*) {
                        inline else => |*p| p.options.id = p.options.id orelse field.name,
                    }
                    parameters_slice[i] = param;
                }

                break :blk .{
                    .context = parameters_context,
                    .log = log,
                    .slice = parameters_slice,
                    .allocator = allocator,
                };
            } else null,
        };
    }

    pub inline fn deinit(self: *Plugin, comptime P: type) void {
        self.allocator.destroy(self.log);

        if (@hasDecl(P, "Parameters")) {
            const params = self.parameters.?;
            self.allocator.free(params.slice);
            const ptr: *P.Parameters = @ptrCast(@alignCast(params.context));
            self.allocator.destroy(ptr);
        }

        self.vtable.deinit(self.context);

        const plugin: *P = @ptrCast(@alignCast(self.context));
        std.heap.page_allocator.destroy(plugin);
    }

    pub inline fn process(self: *Plugin, block: ProcessBlock, params: ?*const anyopaque) !void {
        try self.vtable.process(self.context, block, params);
    }

    pub fn setLog(self: *Plugin, context: *anyopaque, logFn: Log.LogFn) void {
        self.log.context = context;
        self.log.logFn = logFn;
    }
};

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

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
