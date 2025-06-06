const zigplug = @import("zigplug.zig");

const std = @import("std");

fn Options(comptime T: type) type {
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

// TODO: enum parameters

const ParameterType = enum { float, int, uint, bool };

pub const Parameter = union(ParameterType) {
    fn Inner(comptime T: type) type {
        return struct {
            value: std.atomic.Value(T),
            options: Options(T),

            pub fn init(comptime options: Options(T)) @This() {
                if (options.special == .bypass)
                    switch (@typeInfo(T)) {
                        .bool => {},
                        else => @panic("Bypass parameter type must be bool"),
                    };

                return .{
                    .value = .init(options.default),
                    .options = options,
                };
            }

            pub fn set(self: *@This(), value: T) void {
                self.value.store(value, .unordered);
            }

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
pub const Bypass = Parameter{ .bool = .init(.{
    .name = "Bypass",
    .default = false,
    .min = false,
    .max = true,
    .special = .bypass,
}) };
