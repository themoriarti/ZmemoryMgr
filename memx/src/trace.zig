const std = @import("std");

pub const Operation = enum { alloc, free, realloc };

pub const TraceEntry = struct {
    timestamp_ns: i128,
    operation: Operation,
    size: usize,
    alignment: u29,
    type_name: []const u8,
    pointer: usize,
    thread_id: u64,
    arena_id: ?u64 = null,
    pool_id: ?u64 = null,
    duration_ns: u64 = 0,
    stacktrace: []const usize = &.{},
};

pub const TraceBuffer = struct {
    allocator: std.mem.Allocator,
    storage: []TraceEntry,
    stack_storage: []usize,
    capacity: usize,
    cursor: usize = 0,
    filled: bool = false,
    lock: std.Thread.Mutex = .{},
    stack_depth: usize,

    pub fn init(allocator: std.mem.Allocator, capacity: usize, stack_depth: usize) !TraceBuffer {
        if (capacity == 0) return TraceBuffer{
            .allocator = allocator,
            .storage = &.{},
            .stack_storage = &.{},
            .capacity = 0,
            .stack_depth = stack_depth,
        };
        var entries = try allocator.alloc(TraceEntry, capacity);
        var stack = try allocator.alloc(usize, capacity * stack_depth);
        return TraceBuffer{
            .allocator = allocator,
            .storage = entries,
            .stack_storage = stack,
            .capacity = capacity,
            .stack_depth = stack_depth,
        };
    }

    pub fn deinit(self: *TraceBuffer) void {
        if (self.capacity == 0) return;
        self.allocator.free(self.storage);
        self.allocator.free(self.stack_storage);
    }

    pub fn record(self: *TraceBuffer, entry: TraceEntry) void {
        if (self.capacity == 0) return;
        self.lock.lock();
        defer self.lock.unlock();

        const slot = self.cursor % self.capacity;
        self.cursor += 1;
        if (self.cursor >= self.capacity) self.filled = true;

        var stored = entry;
        if (entry.stacktrace.len > 0) {
            const base_index = slot * self.stack_depth;
            const copy_len = @min(entry.stacktrace.len, self.stack_depth);
            const stack_slice = self.stack_storage[base_index .. base_index + copy_len];
            std.mem.copy(usize, stack_slice, entry.stacktrace[0..copy_len]);
            stored.stacktrace = stack_slice;
        } else {
            stored.stacktrace = &.{};
        }
        self.storage[slot] = stored;
    }

    pub fn iter(self: *const TraceBuffer) Iterator {
        const start_index = if (self.filled) self.cursor % self.capacity else 0;
        const remaining = if (self.filled) self.capacity else self.cursor;
        return Iterator{ .buffer = self, .index = start_index, .remaining = remaining };
    }

    pub fn dumpJson(self: *const TraceBuffer, writer: anytype) !void {
        try writer.writeAll("[");
        var it = self.iter();
        var first = true;
        while (it.next()) |entry| {
            if (!first) try writer.writeAll(",");
            first = false;
            try writeEntryJson(writer, entry);
        }
        try writer.writeAll("]");
    }

    fn writeEntryJson(writer: anytype, entry: TraceEntry) !void {
        try writer.print(
            "{\n  \"timestamp_ns\": {d},\n  \"operation\": \"{s}\",\n  \"size\": {d},\n  \"alignment\": {d},\n  \"type\": \"{s}\",\n  \"pointer\": {d},\n  \"thread_id\": {d},\n  \"duration_ns\": {d},\n  \"arena_id\": ",
            .{
                entry.timestamp_ns,
                @tagName(entry.operation),
                entry.size,
                entry.alignment,
                entry.type_name,
                entry.pointer,
                entry.thread_id,
                entry.duration_ns,
            },
        );
        if (entry.arena_id) |arena_id| {
            try writer.print("{d}", .{arena_id});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(",\n  \"pool_id\": ");
        if (entry.pool_id) |pool_id| {
            try writer.print("{d}", .{pool_id});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll("\n}");
    }

    pub const Iterator = struct {
        buffer: *const TraceBuffer,
        index: usize,
        remaining: usize,

        pub fn next(self: *Iterator) ?TraceEntry {
            if (self.remaining == 0 or self.buffer.capacity == 0) return null;
            defer {
                self.index = (self.index + 1) % self.buffer.capacity;
                self.remaining -= 1;
            }
            return self.buffer.storage[self.index];
        }
    };
};

pub fn captureStack(trace_buf: []usize, return_address: usize) []usize {
    _ = trace_buf;
    _ = return_address;
    return &.{};
}

pub fn makeTraceEntry(
    operation: Operation,
    size: usize,
    alignment: u29,
    type_name: []const u8,
    pointer: usize,
    arena_id: ?u64,
    pool_id: ?u64,
    duration_ns: u64,
    stacktrace: []const usize,
) TraceEntry {
    return TraceEntry{
        .timestamp_ns = std.time.nanoTimestamp(),
        .operation = operation,
        .size = size,
        .alignment = alignment,
        .type_name = type_name,
        .pointer = pointer,
        .thread_id = currentThreadId(),
        .arena_id = arena_id,
        .pool_id = pool_id,
        .duration_ns = duration_ns,
        .stacktrace = stacktrace,
    };
}

fn currentThreadId() u64 {
    if (comptime @hasDecl(std.Thread, "getCurrentId")) {
        return @intCast(u64, std.Thread.getCurrentId());
    }
    return 0;
}
