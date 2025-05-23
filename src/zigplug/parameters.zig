// TODO: special bypass parameter

const zigplug = @import("zigplug.zig");

const std = @import("std");

fn Options(comptime T: type) type {
    return struct {
        /// Human-readable, "pretty" name to be displayed by the host or plugin GUI
        name: [:0]const u8,
        /// Parameter will be initialized with this value
        default: T,
        /// This is not a hard limit, a misbehaving host or plugin GUI may end up setting your parameter value beyond these bounds. This is checked by default in debug builds
        min: ?T = switch (@typeInfo(T)) {
            .bool => false,
            .@"enum" => 0,
            else => null,
        },
        /// This is not a hard limit, a misbehaving host or plugin GUI may end up setting your parameter value beyond these bounds. This is checked by default in debug builds
        max: ?T = switch (@typeInfo(T)) {
            .bool => true,
            .@"enum" => |t| t.fields.len - 1,
            else => null,
        },
        automatable: bool = true,
        /// Whether this value increments by integer values
        stepped: bool = switch (@typeInfo(T)) {
            .int, .@"enum", .bool => true,
            else => false,
        },
        /// Optional unit appended to formatted values preceded by a whitespace
        unit: ?[:0]const u8 = null,

        /// Convert a float value to your parameter's type. If null, a generic implementation for primitive types is used
        fromFloat: ?*const fn (value: f64) T = null,
        /// Convert a value of your parameter's type to a float. If null, a generic implementation for primitive types is used
        toFloat: ?*const fn (value: T) f64 = null,
        /// Pretty-print a value of your parameter's type. If null, a generic implementation with `std.fmt.allocPrint` is used
        format: ?*const fn (allocator: std.mem.Allocator, value: T, unit: ?[]const u8) anyerror![]const u8 = null,
        /// Read a value from a string. If null, a generic implementation for primitive types is used
        parse: ?*const fn (value: []const u8, unit: ?[]const u8) anyerror!T = null,
    };
}

pub fn Parameter(
    comptime T: type,
    options: Options(T),
) type {
    return struct {
        pub const Type = T;
        pub const default = options.default;
        pub const min = options.min orelse @compileError("Must specify minimum value for type " ++ @typeName(T));
        pub const max = options.max orelse @compileError("Must specify maximum value for type " ++ @typeName(T));
        pub const name = options.name;
        pub const stepped = options.stepped;
        pub const unit = options.unit;

        /// do not modify directly, use `set()` and `get()`
        value: std.atomic.Value(T) = .init(options.default),

        pub fn set(self: *@This(), value: T) void {
            zigplug.log.debug("param '{s}' = {any}", .{ name, value });
            std.debug.assert(value >= min);
            std.debug.assert(value <= max);
            self.value.store(value, .unordered);
        }

        pub fn get(self: *const @This()) T {
            return self.value.load(.unordered);
        }

        pub fn fromFloat(value: f64) T {
            return if (options.fromFloat) |f| f(value) else genericFromFloat(value, T);
        }

        pub fn toFloat(value: T) f64 {
            return if (options.toFloat) |f| f(value) else genericToFloat(value);
        }

        pub fn setFloat(self: *@This(), value: f64) void {
            self.set(fromFloat(value));
        }

        pub fn getFloat(self: *const @This()) f64 {
            return toFloat(self.get());
        }

        pub fn format(allocator: std.mem.Allocator, value: T) ![]const u8 {
            const f = options.format orelse genericFormat;
            return f(allocator, value, unit);
        }

        pub fn parse(value: []const u8) !T {
            return if (options.parse) |f|
                f(value, unit)
            else
                genericParse(T, unit, value);
        }

        pub fn cast(ptr: *anyopaque) *@This() {
            return @ptrCast(@alignCast(ptr));
        }
    };
}

pub fn genericFromFloat(value: f64, comptime T: type) T {
    return switch (@typeInfo(T)) {
        .float => @floatCast(value),
        .int => @intFromFloat(value),
        .bool => value == 1,
        else => @compileError("fromFloat must be implemented for type " ++ @typeName(T)),
    };
}

pub fn genericToFloat(value: anytype) @TypeOf(value) {
    return switch (@typeInfo(@TypeOf(value))) {
        .float => @floatCast(value),
        .int => @floatFromInt(value),
        .bool => if (value) 1 else 0,
        else => @compileError("toFloat must be implemented for type " ++ @typeName(@TypeOf(value))),
    };
}

pub fn genericFormat(allocator: std.mem.Allocator, value: anytype, comptime unit: ?[]const u8) std.fmt.AllocPrintError![]const u8 {
    const fmt_string = comptime switch (@typeInfo(@TypeOf(value))) {
        .float, .comptime_float => "{d}",
        .pointer, .@"enum" => "{s}",
        else => "{any}",
    };

    const fmt_value = comptime switch (@typeInfo(@TypeOf(value))) {
        .@"enum" => @tagName(value),
        else => value,
    };

    return std.fmt.allocPrint(
        allocator,
        if (unit) |u| fmt_string ++ u else fmt_string,
        .{fmt_value},
    );
}

test genericFormat {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    // float
    try std.testing.expectEqualStrings(
        "1.5",
        try genericFormat(allocator, null, 1.5),
    );
    try std.testing.expectStringStartsWith(
        try genericFormat(allocator, null, 1.0 / 3.0),
        "0.3",
    );

    // int
    try std.testing.expectEqualStrings(
        "0",
        try genericFormat(allocator, null, 0),
    );

    // bool
    try std.testing.expectEqualStrings(
        "true",
        try genericFormat(allocator, null, true),
    );
    try std.testing.expectEqualStrings(
        "false",
        try genericFormat(allocator, null, false),
    );

    // string
    try std.testing.expectEqualStrings(
        "test",
        try genericFormat(allocator, null, "test"),
    );

    // enum
    const Enum = enum { field };
    try std.testing.expectEqualStrings(
        "field",
        try genericFormat(allocator, null, Enum.field),
    );

    // with unit
    try std.testing.expectEqualStrings(
        "6db",
        try genericFormat(allocator, "db", 6),
    );
    try std.testing.expectEqualStrings(
        "44100Hz",
        try genericFormat(allocator, "Hz", 44100),
    );
}

pub fn genericParse(comptime T: type, unit: ?[]const u8, string: []const u8) !T {
    const str = if (unit) |u|
        std.mem.trimRight(u8, string, u)
    else
        string;

    return switch (comptime @typeInfo(T)) {
        .float => std.fmt.parseFloat(T, str),
        .int => |t| try (switch (t.signedness) {
            .signed => std.fmt.parseInt,
            .unsigned => std.fmt.parseUnsigned,
        })(T, str, 10),
        .pointer => |t| if (t.child == u8) str else @compileError("parse must be implemented for type " ++ @typeName(T)),
        .bool => std.mem.eql(u8, str, "true"),
        .@"enum" => std.meta.stringToEnum(T, str) orelse error.FieldNotFound,
        else => @compileError("parse must be implemented for type " ++ @typeName(T)),
    };
}

test genericParse {
    // float
    try std.testing.expectEqual(
        0.5,
        try genericParse(f64, null, "0.5"),
    );

    // int
    try std.testing.expectEqual(
        0,
        try genericParse(i32, null, "-0"),
    );

    // bool
    try std.testing.expectEqual(
        true,
        try genericParse(bool, null, "true"),
    );
    try std.testing.expectEqual(
        false,
        try genericParse(bool, null, "false"),
    );

    // string
    try std.testing.expectEqualStrings(
        "string",
        try genericParse([]const u8, null, "string"),
    );

    // enum
    const Enum = enum { field };
    try std.testing.expectEqual(
        Enum.field,
        try genericParse(Enum, null, "field"),
    );

    // with unit
    try std.testing.expectEqual(
        -6,
        try genericParse(f64, "db", "-6db"),
    );
    try std.testing.expectEqual(
        44100,
        try genericParse(u32, "Hz", "44100Hz"),
    );
}

test "genericFormat == genericParse" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    // float
    try std.testing.expectEqual(
        0.5,
        try genericParse(
            f64,
            null,
            try genericFormat(allocator, null, 0.5),
        ),
    );
    try std.testing.expectEqualStrings(
        "0.5",
        try genericFormat(
            allocator,
            null,
            try genericParse(f64, null, "0.5"),
        ),
    );

    // int
    try std.testing.expectEqual(
        0,
        try genericParse(
            i32,
            null,
            try genericFormat(allocator, null, 0),
        ),
    );
    try std.testing.expectEqualStrings(
        "0",
        try genericFormat(
            allocator,
            null,
            try genericParse(i32, null, "0"),
        ),
    );

    // bool
    try std.testing.expectEqual(
        true,
        try genericParse(
            bool,
            null,
            try genericFormat(allocator, null, true),
        ),
    );
    try std.testing.expectEqualStrings(
        "true",
        try genericFormat(
            allocator,
            null,
            try genericParse(bool, null, "true"),
        ),
    );
    try std.testing.expectEqual(
        false,
        try genericParse(
            bool,
            null,
            try genericFormat(allocator, null, false),
        ),
    );
    try std.testing.expectEqualStrings(
        "false",
        try genericFormat(
            allocator,
            null,
            try genericParse(bool, null, "false"),
        ),
    );

    // string
    try std.testing.expectEqualStrings(
        "string",
        try genericParse(
            []const u8,
            null,
            try genericFormat(allocator, null, "string"),
        ),
    );
    try std.testing.expectEqualStrings(
        "string",
        try genericFormat(
            allocator,
            null,
            try genericParse([]const u8, null, "string"),
        ),
    );

    // enum
    const Enum = enum { field };
    try std.testing.expectEqual(
        Enum.field,
        try genericParse(
            Enum,
            null,
            try genericFormat(allocator, null, Enum.field),
        ),
    );
    try std.testing.expectEqualStrings(
        "field",
        try genericFormat(
            allocator,
            null,
            try genericParse(Enum, null, "field"),
        ),
    );

    // with unit
    try std.testing.expectEqual(
        -6,
        try genericParse(
            f64,
            "db",
            try genericFormat(allocator, "db", -6),
        ),
    );
    try std.testing.expectEqualStrings(
        "-6db",
        try genericFormat(
            allocator,
            "db",
            try genericParse(f64, "db", "-6db"),
        ),
    );
    try std.testing.expectEqual(
        44100,
        try genericParse(
            u32,
            "Hz",
            try genericFormat(allocator, "Hz", 44100),
        ),
    );
    try std.testing.expectEqualStrings(
        "44100Hz",
        try genericFormat(
            allocator,
            "Hz",
            try genericParse(u32, "Hz", "44100Hz"),
        ),
    );
}
