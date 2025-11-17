const zigplug = @import("root.zig");

const std = @import("std");

pub fn Options(comptime T: type) type {
    return struct {
        /// Human-readable, "pretty" name to be displayed by the host or plugin GUI
        name: [:0]const u8,
        /// Optional stable and unique identifier that will be used when saving parameter state. If null, the parameters
        /// struct field name will be used.
        id: ?[]const u8 = null,
        /// Parameter will be initialized with this value
        default: T,
        // TODO: this should automatically be set for booleans and enums
        /// This is not a hard limit, a misbehaving host or plugin GUI may end up setting your parameter value beyond these bounds
        min: T,
        /// This is not a hard limit, a misbehaving host or plugin GUI may end up setting your parameter value beyond these bounds
        max: T,
        automatable: bool = true,
        /// Whether this value increments by integer values
        stepped: bool = switch (@typeInfo(T)) {
            .int, .bool => true,
            else => false,
        },
        /// Optional unit appended to formatted values, possibly preceded by a whitespace
        unit: ?[]const u8 = null,
        /// Some parameters such as bypass get special treatment. See `parameters.Bypass`
        special: ?enum { bypass } = null,

        /// Pretty-print a value to be shown to the user by the host. Make sure that `format(parse(x)) == x`
        ///
        /// It is not necessary to call `std.Io.Writer.flush`
        format: ?*const fn (value: T, writer: *std.Io.Writer) std.Io.Writer.Error!void = null,
        /// Parse a pretty-printed value written by the user. Make sure that `parse(format(x)) == x`
        parse: ?*const fn (value: []const u8) anyerror!T = null,
    };
}

const ParameterType = enum { float, int, uint, bool };

pub const Parameter = union(ParameterType) {
    fn Inner(comptime Type: type) type {
        return struct {
            value: std.atomic.Value(Type),
            options: Options(Type),

            pub fn init(comptime options: Options(Type)) @This() {
                if (options.special == .bypass and Type != bool)
                    @compileError("Bypass parameter type must be bool, got " ++ @typeName(Type));

                if (options.unit != null and options.format != null)
                    @compileError("Parameter '" ++ options.name ++ "' has both `format` and `unit`, which are mutually exclusive");

                return .{
                    .value = .init(options.default),
                    .options = options,
                };
            }

            pub fn set(self: *@This(), value: anytype) void {
                self.value.store(switch (@typeInfo(@TypeOf(value))) {
                    .@"enum" => @intFromEnum(value),
                    else => value,
                }, .unordered);
            }

            // TODO: this for enums
            pub fn get(self: *const @This()) Type {
                return self.value.load(.unordered);
            }

            pub fn fromFloat(value: f64) Type {
                return switch (@typeInfo(Type)) {
                    .float => @floatCast(value),
                    .int => @intFromFloat(value),
                    .bool => value == 1,
                    else => unreachable,
                };
            }

            pub fn toFloat(value: Type) f64 {
                return switch (@typeInfo(@TypeOf(value))) {
                    .float => @floatCast(value),
                    .int => @floatFromInt(value),
                    .bool => if (value) 1 else 0,
                    else => unreachable,
                };
            }

            pub fn format(self: *const @This(), writer: *std.Io.Writer, value: Type) std.Io.Writer.Error!void {
                if (self.options.format) |f|
                    try f(value, writer)
                else
                    try writer.print(
                        switch (@typeInfo(@TypeOf(value))) {
                            .float, .comptime_float => "{d}{s}",
                            else => "{}{s}",
                        },
                        .{ value, self.options.unit orelse "" },
                    );

                try writer.flush();
            }

            pub fn parse(self: *const @This(), value: []const u8) !Type {
                if (self.options.parse) |f|
                    return f(value);

                const str = if (self.options.unit) |u|
                    std.mem.trimRight(u8, value, u)
                else
                    value;

                return switch (comptime @typeInfo(Type)) {
                    .float => std.fmt.parseFloat(Type, str),
                    .int => |t| try (switch (t.signedness) {
                        .signed => std.fmt.parseInt,
                        .unsigned => std.fmt.parseUnsigned,
                    })(Type, str, 10),
                    .bool => std.mem.eql(u8, str, "true"),
                    else => unreachable,
                };
            }
        };
    }

    float: Inner(f64),
    int: Inner(i64),
    uint: Inner(u64),
    bool: Inner(bool),

    /// In some plugin APIs the bypass parameter gets special treatment as it is merged with the host's bypass button.
    /// Create a boolean parameter with `parameters.Parameter` and set `.special = .bypass` if you want to customize the name and default value.
    pub const bypass = Parameter{ .bool = .init(.{
        .name = "Bypass",
        .default = false,
        .min = false,
        .max = true,
        .special = .bypass,
    }) };

    /// Subset of `Options`
    pub fn ChoiceOptions(T: type) type {
        return struct {
            name: [:0]const u8,
            default: T,
            automatable: bool = true,
            /// Map of pretty strings to enum, used for formatting human-readable parameter values. Values that aren't
            /// present in the map will default to `@tagName(x)`.
            ///
            /// Consider initializing with `std.StaticStringMap(T).initComptime`.
            map: ?std.StaticStringMap(T) = null,
        };
    }

    /// Wrap an enum into an integer parameter with automatic formatting. The order of enum values should remain stable
    /// between plugin versions.
    pub fn choice(comptime T: type, comptime options: ChoiceOptions(T)) Parameter {
        switch (@typeInfo(T)) {
            .@"enum" => |info| {
                const callbacks = struct {
                    pub fn format(value: u64, writer: *std.Io.Writer) std.Io.Writer.Error!void {
                        if (value >= @typeInfo(T).@"enum".fields.len) {
                            zigplug.log.err("invalid value for enum {s}: {}", .{ @typeName(T), value });
                            return error.WriteFailed;
                        }
                        const name = blk: {
                            if (options.map) |map|
                                for (map.keys(), map.values()) |k, v|
                                    if (value == @intFromEnum(v))
                                        break :blk k;
                            break :blk std.enums.tagName(T, @enumFromInt(value)).?;
                        };
                        try writer.writeAll(name);
                    }

                    pub fn parse(value: []const u8) error{InvalidEnum}!u64 {
                        if (options.map) |map|
                            if (map.get(value)) |v|
                                return @intFromEnum(v);

                        inline for (info.fields) |field| {
                            if (std.mem.eql(u8, value, field.name))
                                return field.value;
                        }

                        zigplug.log.err("invalid value for enum {s}: '{s}'", .{ @typeName(T), value });
                        return error.InvalidEnum;
                    }
                };

                return .{
                    .uint = .init(.{
                        .name = options.name,
                        .default = @intFromEnum(options.default),
                        .min = 0,
                        .max = info.fields.len - 1,
                        .automatable = options.automatable,
                        .format = callbacks.format,
                        .parse = callbacks.parse,
                    }),
                };
            },
            else => @compileError("Choice type must be an enum, got " ++ @typeName(T)),
        }
    }
};

// TODO: fuzz testing parameter values
test Parameter {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var buffer = std.Io.Writer.Allocating.init(allocator);
    defer buffer.deinit();
    const writer = &buffer.writer;

    const float_param: Parameter = .{ .float = .init(.{
        .name = "Float parameter",
        .default = 0,
        .min = -1,
        .max = 1,
    }) };
    try float_param.float.format(writer, float_param.float.get());
    try std.testing.expectEqual(
        float_param.float.get(),
        try float_param.float.parse(try buffer.toOwnedSlice()),
    );

    const int_param: Parameter = .{ .int = .init(.{
        .name = "Integer parameter",
        .default = 0,
        .min = -100,
        .max = 100,
    }) };
    try int_param.int.format(writer, int_param.int.get());
    try std.testing.expectEqual(
        int_param.int.get(),
        try int_param.int.parse(try buffer.toOwnedSlice()),
    );

    const uint_param: Parameter = .{ .uint = .init(.{
        .name = "Unsigned integer parameter",
        .default = 0,
        .min = 0,
        .max = 100,
    }) };
    try uint_param.uint.format(writer, uint_param.uint.get());
    try std.testing.expectEqual(
        uint_param.uint.get(),
        try uint_param.uint.parse(try buffer.toOwnedSlice()),
    );

    const bool_param: Parameter = .{ .bool = .init(.{
        .name = "Boolean parameter",
        .default = false,
        .min = false,
        .max = true,
    }) };
    try bool_param.bool.format(writer, bool_param.bool.get());
    try std.testing.expectEqual(
        bool_param.bool.get(),
        try bool_param.bool.parse(try buffer.toOwnedSlice()),
    );
}

test "unit and custom formatting" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var int_param = Parameter{
        .int = .init(.{
            .name = "Interval offset",
            .default = 0,
            .min = -(12 * 100 * 5), // -5 octaves
            .max = 12 * 100 * 5, // +5 octaves
            .format = struct {
                pub fn f(value: i64, writer: *std.Io.Writer) std.Io.Writer.Error!void {
                    try writer.print("{s}{} c", .{ switch (std.math.sign(value)) {
                        -1, 0 => "",
                        1 => "+",
                        else => unreachable,
                    }, value });
                }
            }.f,
            .parse = struct {
                pub fn f(value: []const u8) !i64 {
                    return std.fmt.parseInt(
                        i64,
                        std.mem.trimRight(
                            u8,
                            std.mem.trimLeft(u8, std.mem.trimLeft(u8, value, "-"), "+"),
                            " c",
                        ),
                        10,
                    );
                }
            }.f,
        }),
    };

    var buffer = std.Io.Writer.Allocating.init(allocator);
    defer buffer.deinit();
    const writer = &buffer.writer;

    try int_param.int.format(writer, int_param.int.get());
    try std.testing.expectEqualStrings("0 c", try buffer.toOwnedSlice());
    try std.testing.expectEqual(1200, try int_param.int.parse("1200 c"));

    int_param.int.set(1200);
    try int_param.int.format(writer, int_param.int.get());
    try std.testing.expectEqualStrings("+1200 c", try buffer.toOwnedSlice());

    int_param.int.set(-1200);
    try int_param.int.format(writer, int_param.int.get());
    try std.testing.expectEqualStrings("-1200 c", try buffer.toOwnedSlice());
}

test "choice parameter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var buffer = std.Io.Writer.Allocating.init(allocator);
    defer buffer.deinit();
    const writer = &buffer.writer;

    const T = enum { one, two, three };

    var choice_param = Parameter.choice(T, .{
        .name = "Choice parameter",
        .default = .one,
    });
    try choice_param.uint.format(writer, choice_param.uint.get());
    try std.testing.expectEqualStrings("one", try buffer.toOwnedSlice());

    choice_param.uint.set(T.two);
    try choice_param.uint.format(writer, choice_param.uint.get());
    try std.testing.expectEqualStrings("two", try buffer.toOwnedSlice());

    var choice_param_custom_fmt = Parameter.choice(T, .{
        .name = "Choice parameter with custom formatting",
        .default = .one,
        .map = .initComptime(.{
            .{ "1", .one },
            .{ "2", .two },
        }),
    });
    try choice_param_custom_fmt.uint.format(writer, choice_param_custom_fmt.uint.get());
    try std.testing.expectEqualStrings("1", try buffer.toOwnedSlice());

    choice_param_custom_fmt.uint.set(T.two);
    try choice_param_custom_fmt.uint.format(writer, choice_param_custom_fmt.uint.get());
    try std.testing.expectEqualStrings("2", try buffer.toOwnedSlice());

    choice_param_custom_fmt.uint.set(T.three);
    try choice_param_custom_fmt.uint.format(writer, choice_param_custom_fmt.uint.get());
    // `.three` is absent from the static string map so the tag's name should be used
    try std.testing.expectEqualStrings("three", try buffer.toOwnedSlice());
}
