const zigplug = @import("zigplug.zig");

const std = @import("std");

pub fn Options(comptime T: type) type {
    return struct {
        /// Human-readable, "pretty" name to be displayed by the host or plugin GUI
        name: [:0]const u8,
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

        format: ?*const fn (allocator: std.mem.Allocator, value: T, unit: ?[]const u8) anyerror![]const u8 = null,
        parse: ?*const fn (value: []const u8, unit: ?[]const u8) anyerror!T = null,
    };
}

const ParameterType = enum { float, int, uint, bool };

pub const Parameter = union(ParameterType) {
    fn Inner(comptime T: type) type {
        return struct {
            value: std.atomic.Value(T),
            options: Options(T),

            pub fn init(comptime options: Options(T)) @This() {
                if (options.special == .bypass and T != bool)
                    @compileError("Bypass parameter type must be bool, got " ++ @typeName(T));

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
            pub fn get(self: *const @This()) T {
                return self.value.load(.unordered);
            }

            pub fn fromFloat(value: f64) T {
                return switch (@typeInfo(T)) {
                    .float => @floatCast(value),
                    .int => @intFromFloat(value),
                    .bool => value == 1,
                    else => unreachable,
                };
            }

            pub fn toFloat(value: T) f64 {
                return switch (@typeInfo(@TypeOf(value))) {
                    .float => @floatCast(value),
                    .int => @floatFromInt(value),
                    .bool => if (value) 1 else 0,
                    else => unreachable,
                };
            }

            pub fn format(self: *const @This(), allocator: std.mem.Allocator, value: T) ![]const u8 {
                if (self.options.format) |f|
                    return f(allocator, value, self.options.unit);

                const fmt_string = comptime switch (@typeInfo(@TypeOf(value))) {
                    .float, .comptime_float => "{d}",
                    else => "{}",
                };

                return if (self.options.unit) |unit|
                    std.fmt.allocPrint(allocator, fmt_string ++ "{s}", .{ value, unit })
                else
                    std.fmt.allocPrint(allocator, fmt_string, .{value});
            }

            pub fn parse(self: *const @This(), value: []const u8) !T {
                if (self.options.parse) |f|
                    return f(value, self.options.unit);

                const str = if (self.options.unit) |u|
                    std.mem.trimRight(u8, value, u)
                else
                    value;

                return switch (comptime @typeInfo(T)) {
                    .float => std.fmt.parseFloat(T, str),
                    .int => |t| try (switch (t.signedness) {
                        .signed => std.fmt.parseInt,
                        .unsigned => std.fmt.parseUnsigned,
                    })(T, str, 10),
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
};

// TODO: fuzz testing parameter values
test Parameter {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const float_param: Parameter = .{ .float = .init(.{
        .name = "Float parameter",
        .default = 0,
        .min = -1,
        .max = 1,
    }) };
    try std.testing.expectEqual(
        float_param.float.get(),
        try float_param.float.parse(try float_param.float.format(allocator, float_param.float.get())),
    );

    const int_param: Parameter = .{ .int = .init(.{
        .name = "Integer parameter",
        .default = 0,
        .min = -100,
        .max = 100,
    }) };
    try std.testing.expectEqual(
        int_param.int.get(),
        try int_param.int.parse(try int_param.int.format(allocator, int_param.int.get())),
    );

    const uint_param: Parameter = .{ .uint = .init(.{
        .name = "Unsigned integer parameter",
        .default = 0,
        .min = 0,
        .max = 100,
    }) };
    try std.testing.expectEqual(
        uint_param.uint.get(),
        try uint_param.uint.parse(try uint_param.uint.format(allocator, uint_param.uint.get())),
    );

    const bool_param: Parameter = .{ .bool = .init(.{
        .name = "Boolean parameter",
        .default = false,
        .min = false,
        .max = true,
    }) };
    try std.testing.expectEqual(
        bool_param.bool.get(),
        try bool_param.bool.parse(try bool_param.bool.format(allocator, bool_param.bool.get())),
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
            .unit = " c",
            .format = struct {
                pub fn f(ally: std.mem.Allocator, value: i64, unit: ?[]const u8) ![]const u8 {
                    return std.fmt.allocPrint(ally, "{s}{}{s}", .{ switch (std.math.sign(value)) {
                        -1, 0 => "",
                        1 => "+",
                        else => unreachable,
                    }, value, unit.? });
                }
            }.f,
            .parse = struct {
                pub fn f(value: []const u8, unit: ?[]const u8) !i64 {
                    return std.fmt.parseInt(
                        i64,
                        std.mem.trimRight(
                            u8,
                            std.mem.trimLeft(u8, std.mem.trimLeft(u8, value, "-"), "+"),
                            unit.?,
                        ),
                        10,
                    );
                }
            }.f,
        }),
    };

    try std.testing.expectEqualStrings("0 c", try int_param.int.format(allocator, int_param.int.get()));
    try std.testing.expectEqual(1200, try int_param.int.parse("1200 c"));

    int_param.int.set(1200);
    try std.testing.expectEqualStrings("+1200 c", try int_param.int.format(allocator, int_param.int.get()));
    int_param.int.set(-1200);
    try std.testing.expectEqualStrings("-1200 c", try int_param.int.format(allocator, int_param.int.get()));
}

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
        /// Map of pretty strings to enum, used for formatting human-readable parameter values.
        /// Consider initializing with `std.StaticStringMap(T).initComptime`.
        map: ?std.StaticStringMap(T) = null,
    };
}

pub fn choice(comptime T: type, comptime options: ChoiceOptions(T)) Parameter {
    switch (@typeInfo(T)) {
        .@"enum" => |info| {
            const callbacks = struct {
                pub fn format(allocator: std.mem.Allocator, value: u64, unit: ?[]const u8) ![]const u8 {
                    _ = unit; // autofix
                    if (value >= @typeInfo(T).@"enum".fields.len) {
                        zigplug.log.err("invalid value for enum {s}: {}", .{ @typeName(T), value });
                        return error.InvalidEnum;
                    }
                    const name = blk: {
                        if (options.map) |map|
                            for (map.keys(), map.values()) |k, v|
                                if (value == @intFromEnum(v))
                                    break :blk k;
                        break :blk std.enums.tagName(T, @enumFromInt(value)).?;
                    };
                    return std.fmt.allocPrint(allocator, "{s}", .{name});
                }

                pub fn parse(value: []const u8, unit: ?[]const u8) error{InvalidEnum}!u64 {
                    _ = unit; // autofix
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

test choice {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const T = enum { one, two, three };

    var choice_param = choice(T, .{
        .name = "Choice parameter",
        .default = .one,
    });
    try std.testing.expectEqualStrings(
        "one",
        try choice_param.uint.format(allocator, choice_param.uint.get()),
    );
    choice_param.uint.set(T.two);
    try std.testing.expectEqualStrings(
        "two",
        try choice_param.uint.format(allocator, choice_param.uint.get()),
    );

    var choice_param_custom_fmt = choice(T, .{
        .name = "Choice parameter with custom formatting",
        .default = .one,
        .map = .initComptime(.{
            .{ "1", .one },
            .{ "2", .two },
        }),
    });
    try std.testing.expectEqualStrings(
        "1",
        try choice_param_custom_fmt.uint.format(allocator, choice_param_custom_fmt.uint.get()),
    );
    choice_param_custom_fmt.uint.set(T.two);
    try std.testing.expectEqualStrings(
        "2",
        try choice_param_custom_fmt.uint.format(allocator, choice_param_custom_fmt.uint.get()),
    );
    choice_param_custom_fmt.uint.set(T.three);
    // .three is absent from the static string map so the tag's name should be used
    try std.testing.expectEqualStrings(
        "three",
        try choice_param_custom_fmt.uint.format(allocator, choice_param_custom_fmt.uint.get()),
    );
}
