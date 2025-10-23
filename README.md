# ZmemoryMgr

Memx is a Zig allocator toolkit focused on arena/pool workflows with optional tracing and profiling. The package targets Zig 0.13+ and Linux (x86_64 / arm64).

## Layout

```
memx/
  src/        Core allocators and façade
  docs/       Reference material and guides
  examples/   Integration snippets (OCI CLI)
  bench/      Micro and macro benchmark entry points
```

## Building

```
zig build
```

Useful build options:

* `-Ddebug_tracing=true` — enable trace collection.
* `-Djson_logs=stdout` — configure JSON trace sink (informational).
* `-Darena_initial=131072` — adjust initial arena size (bytes).
* `-Dpool_classes="64,128,256"` — select pool slot sizes (first entry currently used).

## Testing

```
zig build test
```

## Example

```
zig build run -Doptimize=Debug -Dtarget=native -Drelease-safe=false -- memx/examples/oci-cli-integr/main.zig
```

(Direct `zig run` is also possible if you provide `-Mmemx=memx/src/memx.zig`.)

## Status

This is an initial implementation that includes:

* Arena allocator with configurable debugging hooks.
* Fixed-size pool allocator with tracing.
* Shared stats aggregation and JSON trace dumping.
* Documentation scaffold covering API, guides and performance expectations.
