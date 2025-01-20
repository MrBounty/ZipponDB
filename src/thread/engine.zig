const std = @import("std");
const U64 = std.atomic.Value(u64);
const Pool = std.Thread.Pool;

const ZipponError = @import("error").ZipponError;
const CPU_CORE = @import("config").CPU_CORE;
const log = std.log.scoped(.thread);

pub const ThreadEngine = @This();

thread_arena: *std.heap.ThreadSafeAllocator,
thread_pool: *Pool,

pub fn init(allocator: std.mem.Allocator) !ThreadEngine {
    const thread_arena = try allocator.create(std.heap.ThreadSafeAllocator);
    thread_arena.* = std.heap.ThreadSafeAllocator{
        .child_allocator = allocator,
    };

    const thread_pool = try allocator.create(std.Thread.Pool);
    thread_pool.init(std.Thread.Pool.Options{
        .allocator = thread_arena.allocator(),
        .n_jobs = CPU_CORE,
    }) catch @panic("=(");

    return ThreadEngine{
        .thread_pool = thread_pool,
        .thread_arena = thread_arena,
    };
}

pub fn deinit(self: *ThreadEngine) void {
    const parent_allocator = self.thread_arena.allocator();
    self.thread_pool.deinit();
    parent_allocator.destroy(self.thread_arena);
    parent_allocator.destroy(self.thread_pool);
}
