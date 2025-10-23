const std = @import("std");
const trace = @import("trace.zig");
const stats = @import("stats.zig");

pub const SizeClass = usize;

pub const Config = struct {
    slot_size: usize = 128,
    capacity: usize = 1024,
    trace_capacity: usize = 1024,
    stack_depth: usize = 8,
};

pub const Error = error{ ObjectTooLarge, OutOfMemory };

pub const PoolAllocator = struct {
    parent: std.mem.Allocator,
    memory: []u8,
    slot_size: usize,
    capacity: usize,
    free_list: ?*Node,
    lock: std.Thread.Mutex = .{},
    stats: *stats.Stats,
    trace_buffer: ?*trace.TraceBuffer,
    debug_tracing: bool,
    id: u64,

    const Node = struct {
        next: ?*Node = null,
    };

    pub fn init(
        parent: std.mem.Allocator,
        config: Config,
        stats_ref: *stats.Stats,
        trace_buffer: ?*trace.TraceBuffer,
        debug_tracing: bool,
        id: u64,
    ) !PoolAllocator {
        const slot_size = @max(config.slot_size, @sizeOf(Node));
        const aligned_slot = std.mem.alignForward(usize, slot_size, @alignOf(Node));
        const total_bytes = aligned_slot * config.capacity;
        var buffer = try parent.alloc(u8, total_bytes);

        var pool = PoolAllocator{
            .parent = parent,
            .memory = buffer,
            .slot_size = aligned_slot,
            .capacity = config.capacity,
            .free_list = null,
            .stats = stats_ref,
            .trace_buffer = trace_buffer,
            .debug_tracing = debug_tracing,
            .id = id,
        };
        pool.bootstrapFreeList();
        return pool;
    }

    fn bootstrapFreeList(self: *PoolAllocator) void {
        var offset: usize = 0;
        while (offset + self.slot_size <= self.memory.len) : (offset += self.slot_size) {
            const node_ptr = @as(*Node, @ptrCast(@alignCast(self.memory.ptr + offset)));
            node_ptr.* = .{ .next = self.free_list };
            self.free_list = node_ptr;
        }
    }

    pub fn deinit(self: *PoolAllocator) void {
        const buffer = self.memory;
        self.parent.free(buffer);
        self.memory = buffer[0..0];
        self.free_list = null;
    }

    pub fn alloc(self: *PoolAllocator, comptime T: type) Error!*T {
        if (@sizeOf(T) > self.slot_size) {
            return Error.ObjectTooLarge;
        }
        const start = std.time.nanoTimestamp();
        self.lock.lock();
        defer self.lock.unlock();

        const node = self.free_list orelse return Error.OutOfMemory;
        self.free_list = node.next;
        const ptr = @as(*T, @ptrCast(node));
        const duration = @as(u64, @intCast(std.time.nanoTimestamp() - start));
        self.stats.recordAlloc(@sizeOf(T), duration);
        if (self.debug_tracing) {
            if (self.trace_buffer) |buffer| {
                var stack_storage: [64]usize = undefined;
                const depth = @min(buffer.stack_depth, stack_storage.len);
                const stack_slice = trace.captureStack(stack_storage[0..depth], @returnAddress());
                buffer.record(trace.makeTraceEntry(
                    .alloc,
                    @sizeOf(T),
                    @alignOf(T),
                    @typeName(T),
                    @intFromPtr(ptr),
                    null,
                    self.id,
                    duration,
                    stack_slice,
                ));
            }
        }
        return ptr;
    }

    pub fn free(self: *PoolAllocator, comptime T: type, ptr: *T) void {
        const start = std.time.nanoTimestamp();
        self.lock.lock();
        defer self.lock.unlock();

        const node_ptr = @as(*Node, @ptrCast(ptr));
        node_ptr.next = self.free_list;
        self.free_list = node_ptr;
        const duration = @as(u64, @intCast(std.time.nanoTimestamp() - start));
        self.stats.recordFree(@sizeOf(T), duration);
        if (self.debug_tracing) {
            if (self.trace_buffer) |buffer| {
                var stack_storage: [64]usize = undefined;
                const depth = @min(buffer.stack_depth, stack_storage.len);
                const stack_slice = trace.captureStack(stack_storage[0..depth], @returnAddress());
                buffer.record(trace.makeTraceEntry(
                    .free,
                    @sizeOf(T),
                    @alignOf(T),
                    @typeName(T),
                    @intFromPtr(ptr),
                    null,
                    self.id,
                    duration,
                    stack_slice,
                ));
            }
        }
    }
};
