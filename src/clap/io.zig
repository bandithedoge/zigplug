const std = @import("std");
const c = @import("clap_c");

pub const WriteError = error{WriteError};

fn clapWriterWrite(stream: *const c.clap_ostream, bytes: []const u8) WriteError!usize {
    const bytes_written = stream.write.?(stream, @ptrCast(bytes), bytes.len);
    if (bytes_written < 0)
        return error.WriteError;
    return @abs(bytes_written);
}

pub const Writer = std.io.Writer(*const c.clap_ostream, WriteError, clapWriterWrite);

pub fn writer(stream: *const c.clap_ostream) Writer {
    return .{ .context = stream };
}

pub const ReadError = error{ReadError};

fn clapReaderRead(stream: *const c.clap_istream, buffer: []u8) ReadError!usize {
    const bytes_read = stream.read.?(stream, @ptrCast(buffer), buffer.len);
    if (bytes_read < 0)
        return error.ReadError;
    return @abs(bytes_read);
}

pub const Reader = std.io.Reader(*const c.clap_istream, ReadError, clapReaderRead);

pub fn reader(stream: *const c.clap_istream) Reader {
    return .{ .context = stream };
}
