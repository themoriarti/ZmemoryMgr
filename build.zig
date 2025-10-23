const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const debug_tracing = b.option(bool, "debug_tracing", "Enable verbose tracing in Memx") orelse false;
    const json_logs = b.option([]const u8, "json_logs", "Optional JSON log destination") orelse "";
    const arena_initial = b.option(u64, "arena_initial", "Initial arena size in bytes") orelse 64 * 1024;
    const arena_growth = b.option(f64, "arena_growth", "Arena growth factor") orelse 2.0;
    const pool_classes = b.option([]const u8, "pool_classes", "Comma separated pool size classes") orelse "128";

    const options = b.addOptions();
    options.addOption(bool, "debug_tracing", debug_tracing);
    options.addOption([]const u8, "json_logs", json_logs);
    options.addOption(u64, "arena_initial", arena_initial);
    options.addOption(f64, "arena_growth", arena_growth);
    options.addOption([]const u8, "pool_classes", pool_classes);

    const memx_module = b.addModule("memx", .{
        .source_file = .{ .path = "memx/src/memx.zig" },
    });
    memx_module.addOptions("memx_build_options", options);

    const lib = b.addStaticLibrary(.{
        .name = "memx",
        .root_source_file = .{ .path = "memx/src/memx.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib.root_module.addOptions("memx_build_options", options);
    b.installArtifact(lib);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "memx/src/memx.zig" },
        .target = target,
        .optimize = optimize,
    });
    unit_tests.root_module.addOptions("memx_build_options", options);

    const test_step = b.step("test", "Run Memx unit tests");
    test_step.dependOn(&unit_tests.step);
}
