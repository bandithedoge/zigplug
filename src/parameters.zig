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
};

/// do not create this directly, use the `<type>Param()` functions
pub const Parameter = struct {
    name: [:0]const u8,
    default: ParameterType,
    min: ParameterType,
    max: ParameterType,

    /// do not modify directly, use `set()` and `get()` to handle types properly
    value: ParameterType = .{ .float = 0.0 },

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
};

pub fn makeParam(param_type: ParameterType, options: Options) Parameter {
    return .{
        .value = param_type,
        .name = options.name,
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
