# Memx Usage Guide

This document explains when to choose the arena or the pool allocator and how to integrate Memx inside long running tools such as OCI runtimes.

## Picking an allocator

| Scenario | Recommended allocator | Notes |
| --- | --- | --- |
| Short lived bulk allocations (parsing configs, building ASTs) | Arena | Reset or drop the arena after the task to reclaim memory in one go. |
| Frequent reuse of fixed-size objects (process descriptors, handle tables) | Pool | Guarantees O(1) allocations and predictable cache behaviour. |
| Interaction with code requiring standard Zig allocator | MemxAllocator | Wraps the arena allocator and can be passed where `std.mem.Allocator` is expected. |

Enable debug tracing during development to validate lifetimes and catch double frees. In release builds the tracing structures can be disabled to avoid overhead.

## Scoped arenas

```zig
var memx = try Memx.init(&allocator, .{ .debug_tracing = true });
var arena_scope = memx.arena();
// allocate temporary data
arena_scope.reset(); // trims temporary allocations
```

## Pool backed structures

```zig
const pool_allocator = memx.pool(128);
var entry = try pool_allocator.alloc(Entry);
entry.* = Entry.init();
// ...
pool_allocator.free(Entry, entry);
```

## Integration tips for OCI runtimes

* Create a single `Memx` instance at process start.
* Derive short lived arenas for each CLI command or sub command to isolate temporary allocations.
* Use pools for high churn structs (namespaces, cgroup descriptors, cached OCI spec fragments).
* On command completion call `Memx.dumpTrace` in debug builds to persist the trace for post-mortem analysis.
