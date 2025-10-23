const std = @import("std");
const trace = @import("trace.zig");
const stats = @import("stats.zig");

pub const TrimStrategy = enum { retain, reset };

pub const Config = struct {
    initial_bytes: usize = 64 * 1024,
    growth_factor: f64 = 2.0,
    max_bytes: ?usize = null,
    trim_strategy: TrimStrategy = .retain,
    trace_capacity: usize = 1024,
    stack_depth: usize = 8,
};

pub const ArenaAllocator = struct {
    parent: std.mem.Allocator,
    inner: std.heap.ArenaAllocator,
    config: Config,
    stats: *stats.Stats,
    trace_buffer: ?*trace.TraceBuffer,
    debug_tracing: bool,
    id: u64,

    pub fn init(
        parent: std.mem.Allocator,
        config: Config,
        stats_ref: *stats.Stats,
        trace_buffer: ?*trace.TraceBuffer,
        debug_tracing: bool,
        id: u64,
    ) !ArenaAllocator {
        var arena = std.heap.ArenaAllocator.init(parent);
        return ArenaAllocator{
            .parent = parent,
            .inner = arena,
            .config = config,
            .stats = stats_ref,
            .trace_buffer = trace_buffer,
            .debug_tracing = debug_tracing,
            .id = id,
        };
    }

    pub fn deinit(self: *ArenaAllocator) void {
        self.inner.deinit();
    }

    pub fn allocator(self: *ArenaAllocator) std.mem.Allocator {
        return self.inner.allocator();
    }

    pub fn reset(self: *ArenaAllocator) void {
        self.inner.deinit();
        self.inner = std.heap.ArenaAllocator.init(self.parent);
    }

    pub fn alloc(self: *ArenaAllocator, comptime T: type, n: usize) ![]T {
        const alloc_start = std.time.nanoTimestamp();
        var result = try self.allocator().alloc(T, n);
        const duration = @as(u64, @intCast(std.time.nanoTimestamp() - alloc_start));
        const total_size = @sizeOf(T) * n;
        self.stats.recordAlloc(total_size, duration);
        if (self.debug_tracing) {
            if (self.trace_buffer) |buffer| {
                var stack_storage: [64]usize = undefined;
                const depth = @min(self.config.stack_depth, stack_storage.len);
                const stack_slice = trace.captureStack(stack_storage[0..depth], @returnAddress());
                buffer.record(trace.makeTraceEntry(
                    .alloc,
                    total_size,
                    @alignOf(T),
                    @typeName(T),
                    @intFromPtr(result.ptr),
                    self.id,
                    null,
                    duration,
                    stack_slice,
                ));
            }
        }
        return result;
    }

    pub fn free(self: *ArenaAllocator, comptime T: type, slice: []T) void {
        const free_start = std.time.nanoTimestamp();
        self.allocator().free(slice);
        const duration = @as(u64, @intCast(std.time.nanoTimestamp() - free_start));
        const total_size = @sizeOf(T) * slice.len;
        self.stats.recordFree(total_size, duration);
        if (self.debug_tracing) {
            if (self.trace_buffer) |buffer| {
                var stack_storage: [64]usize = undefined;
                const depth = @min(self.config.stack_depth, stack_storage.len);
                const stack_slice = trace.captureStack(stack_storage[0..depth], @returnAddress());
                buffer.record(trace.makeTraceEntry(
                    .free,
                    total_size,
                    @alignOf(T),
                    @typeName(T),
                    @intFromPtr(slice.ptr),
                    self.id,
                    null,
                    duration,
                    stack_slice,
                ));
            }
        }
    }
};
