const std = @import("std");
const U64 = std.atomic.Value(u64);
const Pool = std.Thread.Pool;

const ZipponError = @import("error").ZipponError;
const CPU_CORE = @import("config").CPU_CORE;
const log = std.log.scoped(.thread);

const allocator = std.heap.page_allocator;

var thread_arena: std.heap.ThreadSafeAllocator = undefined;
var thread_pool: Pool = undefined;

pub const ThreadEngine = @This();

thread_arena: *std.heap.ThreadSafeAllocator,
thread_pool: *Pool,

pub fn init() ThreadEngine {
    thread_arena = std.heap.ThreadSafeAllocator{
        .child_allocator = allocator,
    };

    thread_pool.init(std.Thread.Pool.Options{
        .allocator = thread_arena.allocator(),
        .n_jobs = CPU_CORE,
    }) catch @panic("=(");

    return ThreadEngine{
        .thread_pool = &thread_pool,
        .thread_arena = &thread_arena,
    };
}

pub fn deinit(_: ThreadEngine) void {
    thread_pool.deinit();
}
