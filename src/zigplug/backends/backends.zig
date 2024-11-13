const pugl = @import("pugl.zig");

pub const OpenGl = .{
    .backend = pugl.openGl,
    .c = pugl.c,
};

pub const Cairo = .{
    .backend = pugl.cairo,
    .c = pugl.c,
};

// TODO: vulkan
