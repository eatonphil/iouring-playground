const std = @import("std");

fn readFile(inFile: std.fs.File, inControl: []const u8) !u64 {
    const size = try inFile.getEndPos();

    var buf = [_]u8{0} ** 4096;
    var read: usize = 0;
    while (read < size) {
        var nread = try inFile.read(buf[0..]);
        std.debug.assert(std.mem.eql(
            u8,
            inControl[read .. read + nread],
            buf[0..nread],
        ));
        read += nread;
    }
    std.debug.assert(read == size);
    return size;
}

fn readFileIOUring(inFile: std.fs.File, inControl: []const u8) !u64 {
    const nEntries: u13 = 1024;
    var ring = std.os.linux.IO_Uring.init(nEntries, 0) catch |err| {
        std.debug.panic("Failed to initialize io_uring: {}\n", .{err});
        return;
    };
    defer ring.deinit();

    const fileSize = try inFile.getEndPos();

    const bufferSize: u64 = 4096;
    var buffers: [nEntries][bufferSize]u8 = undefined;
    var readbuffers: [nEntries]std.os.linux.IO_Uring.ReadBuffer = undefined;
    for (&readbuffers, 0..) |*readbuffer, i| {
        readbuffer.* = .{ .buffer = &buffers[i] };
    }

    var cqes: [nEntries]std.os.linux.io_uring_cqe = undefined;

    var read: usize = 0;
    var bytesSubmitted: usize = 0;
    while (bytesSubmitted < fileSize) : (bytesSubmitted += bufferSize * nEntries) {
        var entriesSubmitted: u32 = 0;
        var entry: usize = 0;
        while (entry < nEntries) : (entry += 1) {
            const offset = bytesSubmitted + bufferSize * entry;
            if (offset > fileSize) {
                break;
            }
            entriesSubmitted += 1;
            _ = try ring.read(0, inFile.handle, readbuffers[entry], offset);
        }

        const submitted = ring.submit_and_wait(entriesSubmitted) catch unreachable;
        std.debug.assert(submitted == entriesSubmitted);

        const waited = ring.copy_cqes(cqes[0..submitted], submitted) catch unreachable;
        std.debug.assert(waited == submitted);

        for (cqes[0..submitted], 0..) |*cqe, i| {
            if (cqe.err() != .SUCCESS) {
                @panic("Request failed");
            }

            const n = @as(usize, @intCast(cqe.res));
            std.debug.assert(n <= bufferSize);

            std.debug.assert(std.mem.eql(
                u8,
                inControl[read .. read + n],
                buffers[i][0..n],
            ));

            read += n;
        }
    }
    std.debug.assert(read == fileSize);
    return fileSize;
}

pub fn main() !void {
    var i: usize = 0;
    const filename = "in.txt";

    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const allocator = std.heap.page_allocator;
    var maxSize: usize = 0;
    maxSize = maxSize -% 1;
    const data = try file.readToEndAlloc(allocator, maxSize);
    defer allocator.free(data);

    while (i < 10) : (i += 1) {
        try file.seekTo(0);
        var t1 = try std.time.Instant.now();
        var size = try readFile(file, data);
        var t2 = try std.time.Instant.now();
        var s = @as(f64, @floatFromInt(t2.since(t1))) / std.time.ns_per_s;
        try std.io.getStdOut().writer().print(
            "read,{d},{d}\n",
            .{ s, @as(f64, @floatFromInt(size)) / s },
        );

        try file.seekTo(0);
        t1 = try std.time.Instant.now();
        size = try readFileIOUring(file, data);
        t2 = try std.time.Instant.now();
        s = @as(f64, @floatFromInt(t2.since(t1))) / std.time.ns_per_s;
        try std.io.getStdOut().writer().print(
            "iouring,{d},{d}\n",
            .{ s, @as(f64, @floatFromInt(size)) / s },
        );
    }
}
