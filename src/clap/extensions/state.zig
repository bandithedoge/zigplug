const c = @import("clap_c");
const clap = @import("clap");
const msgpack = @import("msgpack");

const std = @import("std");
const log = std.log.scoped(.zigplug_clap_state);

// TODO: make Writer and Reader buffered

pub const Writer = struct {
    clap_stream: *const c.clap_ostream,
    writer: std.Io.Writer,

    pub fn init(clap_stream: *const c.clap_ostream) Writer {
        return .{
            .clap_stream = clap_stream,
            .writer = .{
                .vtable = &.{
                    .drain = drain,
                },
                .buffer = &.{},
            },
        };
    }

    fn drain(writer: *std.Io.Writer, data: []const []const u8, _: usize) std.Io.Writer.Error!usize {
        const self: *Writer = @fieldParentPtr("writer", writer);
        var total_written: usize = 0;
        for (data) |bytes| {
            const written = self.clap_stream.write.?(self.clap_stream, bytes.ptr, bytes.len);
            if (written == -1)
                return error.WriteFailed;
            total_written += @abs(written);
        }
        return total_written;
    }
};

const Reader = struct {
    clap_stream: *const c.clap_istream,
    reader: std.Io.Reader,

    pub fn init(clap_stream: *const c.clap_istream) Reader {
        return .{
            .clap_stream = clap_stream,
            .reader = .{
                .vtable = &.{
                    .stream = stream,
                },
                .buffer = &.{},
                .seek = 0,
                .end = 0,
            },
        };
    }

    fn stream(reader: *std.Io.Reader, writer: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
        const self: *Reader = @fieldParentPtr("reader", reader);
        while (true) {
            const buffer = try writer.writableSliceGreedy(limit.toInt() orelse 64);
            switch (self.clap_stream.read.?(self.clap_stream, buffer.ptr, buffer.len)) {
                -1 => return error.ReadFailed,
                0 => return error.EndOfStream,
                else => |read| {
                    writer.advance(@abs(read));
                    return @abs(read);
                },
            }
        }
    }
};

pub fn extension(comptime Plugin: type) *const c.clap_plugin_state {
    const state = struct {
        pub fn save(clap_plugin: [*c]const c.clap_plugin, stream: [*c]const c.clap_ostream) callconv(.c) bool {
            const data = clap.Data.fromClap(clap_plugin);

            var clap_writer = Writer.init(stream);
            const writer = &clap_writer.writer;

            var reader = std.Io.Reader.failing;
            var packer = msgpack.packIO(&reader, writer);

            var map = msgpack.Payload.mapPayload(data.plugin.allocator);
            defer map.free(data.plugin.allocator);

            inline for (data.plugin.parameters.?.slice, std.meta.fields(Plugin.Parameters)) |parameter, field| {
                map.mapPut(field.name, switch (parameter.*) {
                    .bool => |p| .boolToPayload(p.get()),
                    .float => |p| .floatToPayload(p.get()),
                    .int => |p| .intToPayload(p.get()),
                    .uint => |p| .uintToPayload(p.get()),
                }) catch {
                    switch (parameter.*) {
                        inline else => |p| {
                            log.err("failed to save parameter '{s}' = {any}", .{ p.options.name, p.get() });
                            return false;
                        },
                    }
                };

                switch (parameter.*) {
                    inline else => |p| log.debug("saved parameter '{s}' = {any}", .{ field.name, p.get() }),
                }
            }

            packer.write(map) catch {
                log.err("failed to save parameters", .{});
                return false;
            };

            return true;
        }

        pub fn load(clap_plugin: [*c]const c.clap_plugin, stream: [*c]const c.clap_istream) callconv(.c) bool {
            const data = clap.Data.fromClap(clap_plugin);
            var clap_reader = Reader.init(stream);
            const reader = &clap_reader.reader;

            var writer = std.Io.Writer.failing;
            var packer = msgpack.packIO(reader, &writer);

            const decoded = packer.read(data.plugin.allocator) catch {
                log.err("failed to read parameters", .{});
                return false;
            };
            defer decoded.free(data.plugin.allocator);

            inline for (data.plugin.parameters.?.slice, std.meta.fields(Plugin.Parameters)) |parameter, field| {
                if (decoded.mapGet(field.name) catch {
                    log.err("failed to read parameter '{s}'", .{field.name});
                    return false;
                }) |value| {
                    switch (parameter.*) {
                        .bool => |*p| p.set(value.bool),
                        .float => |*p| p.set(value.float),
                        .int => |*p| p.set(value.int),
                        .uint => |*p| p.set(value.uint),
                    }
                }

                switch (parameter.*) {
                    inline else => |p| log.debug("read parameter '{s}' = {any}", .{ field.name, p.get() }),
                }
            }

            return true;
        }
    };

    return &.{
        .save = state.save,
        .load = state.load,
    };
}
