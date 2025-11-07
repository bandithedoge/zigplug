// TODO: use some sort of actual binary serialization
// libs to consider:
// - https://github.com/ziglibs/s2s
// - https://github.com/SeanTheGleaming/zig-serialization
// - https://codeberg.org/hDS9HQLN/ztsl

const c = @import("clap_c");
const clap = @import("clap");

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

pub fn extension(comptime _: type) *const c.clap_plugin_state {
    const state = struct {
        pub fn save(clap_plugin: [*c]const c.clap_plugin, stream: [*c]const c.clap_ostream) callconv(.c) bool {
            const data = clap.Data.fromClap(clap_plugin);
            var clap_writer = Writer.init(stream);
            const writer = &clap_writer.writer;

            for (data.plugin.parameters.?.slice) |parameter| {
                switch (parameter.*) {
                    inline else => |p| {
                        const value = p.get();
                        const bytes = std.mem.asBytes(&value);
                        writer.writeAll(bytes) catch {
                            log.err("failed to save parameter '{s}' = {}", .{ p.options.name, value });
                            return false;
                        };
                        log.debug("saved parameter '{s}' = {any}", .{ p.options.name, value });
                    },
                }
            }

            return true;
        }

        pub fn load(clap_plugin: [*c]const c.clap_plugin, stream: [*c]const c.clap_istream) callconv(.c) bool {
            const data = clap.Data.fromClap(clap_plugin);
            var clap_reader = Reader.init(stream);
            const reader = &clap_reader.reader;

            for (data.plugin.parameters.?.slice) |parameter| switch (parameter.*) {
                inline else => |*p| {
                    var value = p.get();
                    const buffer = std.mem.asBytes(&value);
                    reader.readSliceAll(buffer) catch {
                        log.err("failed to load parameter '{s}'", .{p.options.name});
                        return false;
                    };
                    p.set(value);

                    log.debug("loaded parameter '{s}' = {any}", .{ p.options.name, value });
                },
            };

            return false;
        }
    };

    return &.{
        .save = state.save,
        .load = state.load,
    };
}
