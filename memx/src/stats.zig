const std = @import("std");

pub const Percentiles = struct {
    p50: u64 = 0,
    p95: u64 = 0,
    p99: u64 = 0,
};

pub const Stats = struct {
    alloc_count: usize = 0,
    free_count: usize = 0,
    bytes_allocated: usize = 0,
    bytes_freed: usize = 0,
    high_water_mark: usize = 0,
    current_bytes: usize = 0,
    total_nanoseconds: u128 = 0,

    percentiles: Percentiles = .{},

    pub fn recordAlloc(self: *Stats, size: usize, duration_ns: u64) void {
        self.alloc_count += 1;
        self.bytes_allocated += size;
        self.current_bytes += size;
        if (self.current_bytes > self.high_water_mark) {
            self.high_water_mark = self.current_bytes;
        }
        self.total_nanoseconds += duration_ns;
    }

    pub fn recordFree(self: *Stats, size: usize, duration_ns: u64) void {
        self.free_count += 1;
        self.bytes_freed += size;
        if (self.current_bytes >= size) {
            self.current_bytes -= size;
        } else {
            self.current_bytes = 0;
        }
        self.total_nanoseconds += duration_ns;
    }

    pub fn mergePercentiles(self: *Stats, allocator: std.mem.Allocator, samples: []const u64) void {
        if (samples.len == 0) return;
        var buffer = allocator.alloc(u64, samples.len) catch {
            return;
        };
        defer allocator.free(buffer);
        @memcpy(buffer, samples);
        insertionSort(buffer);

        self.percentiles.p50 = percentile(buffer, 50);
        self.percentiles.p95 = percentile(buffer, 95);
        self.percentiles.p99 = percentile(buffer, 99);
    }

    pub fn reset(self: *Stats) void {
        self.* = Stats{};
    }
};

fn percentile(values: []const u64, p: u8) u64 {
    if (values.len == 0) return 0;
    const idx = (values.len - 1) * p / 100;
    return values[idx];
}

fn insertionSort(values: []u64) void {
    var i: usize = 1;
    while (i < values.len) : (i += 1) {
        const key = values[i];
        var j = i;
        while (j > 0 and values[j - 1] > key) : (j -= 1) {
            values[j] = values[j - 1];
        }
        values[j] = key;
    }
}
