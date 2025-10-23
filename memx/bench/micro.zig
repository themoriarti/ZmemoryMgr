const std = @import("std");
const Memx = @import("memx").Memx;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();

    var memx = try Memx.init(&allocator, Memx.Config.default_config);
    defer memx.deinit();

    var timer = try std.time.Timer.start();
    var total: usize = 0;
    for (0..100_000) |_| {
        const slice = try memx.makeSlice(u8, 64);
        defer memx.free(u8, slice);
        total += slice.len;
    }
    const elapsed = timer.read();
    try std.io.getStdOut().writer().print("micro benchmark total={d} elapsed_ns={d}\n", .{ total, elapsed });
}
