// TODO: enum parameters
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
        // TODO: actually check this condition
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
        fromFloat: ?*const fn (f64) T = null,
        /// Convert a value of your parameter's type to a float. If null, a generic implementation for primitive types is used
        toFloat: ?*const fn (T) f64 = null,
        /// Pretty-print a value of your parameter's type. If null, a generic implementation with `std.fmt.allocPrint` is used
        format: ?*const fn (T, std.mem.Allocator) []const u8 = null,
        // TODO: parse function
    };
}

pub fn Parameter(
    comptime T: type,
    options: Options(T),
) type {
    return struct {
        pub const default = options.default;
        pub const min = options.min orelse @compileError("Must specify minimum value for type " ++ @typeName(T));
        pub const max = options.max orelse @compileError("Must specify maximum value for type " ++ @typeName(T));
        pub const name = options.name;
        pub const stepped = options.stepped;
        pub const unit = options.unit;

        /// do not modify directly, use `set()` and `get()`
        value: std.atomic.Value(T) = .init(options.default),

        pub fn set(self: *@This(), value: T) void {
            zigplug.log.debug("param '{s}' = {}", .{name, value});
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

        pub fn print(self: *const @This(), allocator: std.mem.Allocator) []const u8 {
            return if (options.format) |f| f(self.get, allocator) else genericPrint(self.get(), allocator);
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

pub fn genericPrint(value: anytype, allocator: std.mem.Allocator) []const u8 {
    return std.fmt.allocPrint(allocator, switch (@typeInfo(@TypeOf(value))) {
        .float => "{d}",
        else => "{}",
    }, .{value});
}
