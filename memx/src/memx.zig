const std = @import("std");
const arena = @import("arena.zig");
const pool = @import("pool.zig");
const stats = @import("stats.zig");
const trace = @import("trace.zig");
const build_options = @import("memx_build_options");

pub const Memx = struct {
    pub const Config = struct {
        debug_tracing: bool = false,
        json_logs: ?[]const u8 = null,
        arena: arena.Config = .{},
        pool: pool.Config = .{},
        trace_capacity: usize = 2048,
        stack_depth: usize = 16,
    };

    pub const default_config: Config = .{
        .debug_tracing = build_options.debug_tracing,
        .json_logs = if (build_options.json_logs.len == 0) null else build_options.json_logs,
        .arena = .{
            .initial_bytes = @intCast(usize, build_options.arena_initial),
            .growth_factor = build_options.arena_growth,
        },
        .pool = .{
            .slot_size = parseFirstClass(build_options.pool_classes),
        },
        .trace_capacity = 2048,
        .stack_depth = 16,
    };

    upstream: std.mem.Allocator,
    config: Config,
    stats_state: stats.Stats = .{},
    arena_allocator: arena.ArenaAllocator,
    pool_allocator: pool.PoolAllocator,
    trace_buffer: ?trace.TraceBuffer = null,
    next_id: std.atomic.Value(u64) = std.atomic.Value(u64).init(1),

    pub fn init(upstream_ptr: *std.mem.Allocator, cfg: Config) !Memx {
        var memx = Memx{
            .upstream = upstream_ptr.*,
            .config = cfg,
            .stats_state = .{},
            .arena_allocator = undefined,
            .pool_allocator = undefined,
            .trace_buffer = null,
        };

        if (cfg.debug_tracing) {
            memx.trace_buffer = try trace.TraceBuffer.init(
                memx.upstream,
                cfg.trace_capacity,
                cfg.stack_depth,
            );
        }

        const trace_ptr = if (memx.trace_buffer) |*buffer| buffer else null;
        memx.arena_allocator = try arena.ArenaAllocator.init(
            memx.upstream,
            cfg.arena,
            &memx.stats_state,
            trace_ptr,
            cfg.debug_tracing,
            memx.nextId(),
        );
        memx.pool_allocator = try pool.PoolAllocator.init(
            memx.upstream,
            cfg.pool,
            &memx.stats_state,
            trace_ptr,
            cfg.debug_tracing,
            memx.nextId(),
        );
        return memx;
    }

    fn nextId(self: *Memx) u64 {
        return self.next_id.fetchAdd(1, .monotonic);
    }

    pub fn deinit(self: *Memx) void {
        self.arena_allocator.deinit();
        self.pool_allocator.deinit();
        if (self.trace_buffer) |*buffer| buffer.deinit();
    }

    pub fn arena(self: *Memx) *arena.ArenaAllocator {
        return &self.arena_allocator;
    }

    pub fn pool(self: *Memx, class: pool.SizeClass) *pool.PoolAllocator {
        _ = class;
        return &self.pool_allocator;
    }

    pub fn alloc(self: *Memx, comptime T: type, n: usize) ![]T {
        return self.arena_allocator.alloc(T, n);
    }

    pub fn free(self: *Memx, comptime T: type, slice: []T) void {
        self.arena_allocator.free(T, slice);
    }

    pub fn make(self: *Memx, comptime T: type) !*T {
        var slice = try self.alloc(T, 1);
        return &slice[0];
    }

    pub fn makeSlice(self: *Memx, comptime T: type, n: usize) ![]T {
        return self.alloc(T, n);
    }

    pub fn dupe(self: *Memx, comptime T: type, src: []const T) ![]T {
        var dst = try self.alloc(T, src.len);
        std.mem.copy(T, dst, src);
        return dst;
    }

    pub fn stats(self: *Memx) stats.Stats {
        return self.stats_state;
    }

    pub fn dumpTrace(self: *Memx, writer: anytype) !void {
        if (self.trace_buffer) |buffer| {
            try buffer.dumpJson(writer);
        }
    }

    pub fn allocator(self: *Memx) std.mem.Allocator {
        return self.arena_allocator.allocator();
    }

    pub fn memxAllocator(self: *Memx) MemxAllocator {
        return MemxAllocator{ .arena = &self.arena_allocator };
    }
};

pub const MemxAllocator = struct {
    arena: *arena.ArenaAllocator,

    pub fn allocator(self: *MemxAllocator) std.mem.Allocator {
        return self.arena.allocator();
    }
};

fn parseFirstClass(list: []const u8) usize {
    var it = std.mem.tokenizeScalar(u8, list, ',');
    if (it.next()) |token| {
        return std.fmt.parseInt(usize, token, 10) catch 128;
    }
    return 128;
}

test "memx arena make and free" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        std.debug.assert(!leaked);
    }
    var allocator = gpa.allocator();
    var memx = try Memx.init(&allocator, .{ .debug_tracing = false });
    defer memx.deinit();

    const slice = try memx.makeSlice(u32, 4);
    defer memx.free(u32, slice);
    slice[0] = 42;
    slice[1] = 43;
    try std.testing.expectEqual(@as(u32, 42), slice[0]);
}

test "memx pool alloc and free" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        std.debug.assert(!leaked);
    }
    var allocator = gpa.allocator();
    var memx = try Memx.init(&allocator, .{ .debug_tracing = false, .pool = .{ .slot_size = 64, .capacity = 16 } });
    defer memx.deinit();

    const pool_allocator = memx.pool(64);
    var node = try pool_allocator.alloc(u32);
    defer pool_allocator.free(u32, node);
    node.* = 99;
    try std.testing.expectEqual(@as(u32, 99), node.*);
}
