# Memx API Overview

`Memx` provides a consolidated façade over the arena and pool allocators implemented in this package. The public API is available from `memx/src/memx.zig` and exposes convenience helpers in addition to accessors for the underlying allocators.

## Initialization

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator = gpa.allocator();
var memx = try Memx.init(&allocator, Memx.Config.default_config);
```

`Memx.Config.default_config` honours build options passed via `zig build`. The structure can be customised per call.

## Allocation helpers

* `alloc(T, n)` — reserves `n` elements of type `T` from the arena.
* `free(T, slice)` — releases memory back to the arena.
* `make(T)` / `makeSlice(T, n)` — convenience wrappers that call `alloc` and return a pointer/slice respectively.
* `dupe(T, slice)` — duplicates a slice into arena managed memory.

## Pool allocator

`memx.pool(size_class)` returns the configured pool allocator. The default implementation exposes a single pool class sized according to the build option `-Dpool_classes` (first entry is used).

The pool allocator offers `alloc(T)` and `free(T, ptr)` with constant time semantics for objects that fit the configured slot size.

## Tracing and statistics

Tracing is controlled via `Memx.Config.debug_tracing`. When enabled, each allocation/free event updates the shared `Stats` structure and records trace entries in a ring buffer. Use `Memx.dumpTrace(writer)` to serialise the current buffer as JSON.

`Memx.stats()` returns a copy of the aggregated metrics which include operation counts, bytes moved, high water mark and cumulative nanoseconds spent.
