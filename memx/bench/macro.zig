const std = @import("std");
const Memx = @import("memx").Memx;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();

    var memx = try Memx.init(&allocator, Memx.Config.default_config);
    defer memx.deinit();

    const iterations = 128;
    var total_bytes: usize = 0;
    var timer = try std.time.Timer.start();
    for (0..iterations) |_| {
        const config = try memx.makeSlice(u8, 8192);
        total_bytes += config.len;
        memx.free(u8, config);
        var proc = try memx.pool(128).alloc(Descriptor);
        proc.* = .{ .id = @as(u32, @intCast(total_bytes % 1000)), .state = .ready };
        memx.pool(128).free(Descriptor, proc);
    }
    const elapsed = timer.read();
    try std.io.getStdOut().writer().print("macro benchmark iterations={d} bytes={d} elapsed_ns={d}\n", .{ iterations, total_bytes, elapsed });
}

const Descriptor = struct {
    id: u32,
    state: State,
};

enum State { ready, running, finished }
