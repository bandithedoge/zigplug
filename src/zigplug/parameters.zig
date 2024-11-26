// TODO: enum parameters

const std = @import("std");

pub const ParameterType = union(enum) {
    float: f32,
    int: i32,
    uint: u32,
    bool: bool,

    pub fn toFloat(self: *const ParameterType) f64 {
        return switch (self.*) {
            .float => self.float,
            .int => @floatFromInt(self.int),
            .uint => @floatFromInt(self.uint),
            .bool => if (self.bool) 1.0 else 0.0,
        };
    }

    pub fn fromFloat(self: *ParameterType, value: f64) void {
        switch (self.*) {
            .float => {
                self.float = @floatCast(value);
            },
            .int => {
                self.int = @intFromFloat(value);
            },
            .uint => {
                self.uint = @intFromFloat(value);
            },
            .bool => {
                self.bool = value == 1.0;
            },
        }
    }

    pub fn print(self: *const ParameterType, allocator: std.mem.Allocator) ![:0]const u8 {
        return switch (self.*) {
            .float => std.fmt.allocPrintZ(allocator, "{d}", .{self.float}),
            .int => std.fmt.allocPrintZ(allocator, "{d}", .{self.int}),
            .uint => std.fmt.allocPrintZ(allocator, "{d}", .{self.int}),
            .bool => if (self.bool) "true" else "false",
        };
    }
};

/// do not create this directly, use the `<type>Param()` functions
pub const Parameter = struct {
    name: [:0]const u8,
    default: ParameterType,
    min: ParameterType,
    max: ParameterType,
    unit: ?[:0]const u8 = null,

    /// do not modify directly, use `set()` and `get()` to handle types properly
    value: ParameterType = .{ .float = 0.0 },
    changed: bool = false,

    main_changed: bool = false,
    main_value: ParameterType = undefined,

    pub fn set(self: *Parameter, val: ParameterType) void {
        self.value = val;
    }

    pub fn get(self: *const Parameter) ParameterType {
        return self.value;
    }
};

const Options = struct {
    name: [:0]const u8,
    min: ?ParameterType = null,
    max: ?ParameterType = null,
    unit: ?[:0]const u8 = null,
};

pub fn makeParam(param_type: ParameterType, options: Options) Parameter {
    return .{
        .value = param_type,
        .name = options.name,
        .unit = options.unit,
        .default = param_type,
        .min = options.min orelse switch (param_type) {
            .float => .{ .float = 0.0 },
            .int => .{ .int = 0 },
            .uint => .{ .uint = 0 },
            .bool => .{ .bool = false },
        },
        .max = options.max orelse switch (param_type) {
            .float => .{ .float = 1.0 },
            .int => .{ .int = 1 },
            .uint => .{ .uint = 1 },
            .bool => .{ .bool = true },
        },
    };
}
