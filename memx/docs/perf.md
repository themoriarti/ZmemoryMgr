# Performance Notes

Memx is designed to outperform `std.heap.GeneralPurposeAllocator` for workloads dominated by small object management.

## Micro benchmarks

* Size classes: 16, 32, 64, 128, 256 bytes.
* Patterns: LIFO, FIFO and random sequences with 1:1 and 3:1 alloc/free ratios.
* Target speed-up: >= 20% throughput improvement in debug and release modes for arena/pool compared to GPA.

## Macro scenarios

* Parsing OCI `config.json` files into temporary structures held in an arena.
* Populating process namespace descriptors from a pool to avoid heap churn.
* Simulating registry watchers where descriptors are retained/recycled frequently.

## Tracing overhead

Debug tracing aims to stay under 3x of the release build cost. The ring buffer avoids dynamic allocations; JSON emission is typically deferred to shutdown time.

## Tips

* Adjust `-Darena_initial` and `-Darena_growth` to fit expected working sets.
* Tune `-Dpool_classes` to match the dominant object sizes in your runtime.
* Disable tracing in release builds for minimum overhead.
