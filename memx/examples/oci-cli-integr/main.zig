const std = @import("std");
const Memx = @import("memx").Memx;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();

    var memx = try Memx.init(&allocator, Memx.Config.default_config);
    defer memx.deinit();

    // Simulate parsing an OCI config into an arena owned slice
    const config_blob = try memx.makeSlice(u8, 4096);
    defer memx.free(u8, config_blob);
    try std.io.getStdOut().writer().print("allocated config buffer of {d} bytes\n", .{config_blob.len});

    // Manage process descriptors via the pool allocator
    const Process = struct {
        pid: u32,
        name: [32]u8,
    };

    const process_pool = memx.pool(128);
    var proc = try process_pool.alloc(Process);
    defer process_pool.free(Process, proc);
    proc.* = .{ .pid = 42, .name = .{0} ** 32 };
    std.mem.copy(u8, proc.name[0.."oci-task".len], "oci-task");
    try std.io.getStdOut().writer().print("process pid={d}\n", .{proc.pid});
}
