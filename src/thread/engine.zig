const std = @import("std");
const Pool = std.Thread.Pool;
const Allocator = std.mem.Allocator;

const CPU_CORE = @import("config").CPU_CORE;
const log = std.log.scoped(.thread);
const ZipponError = @import("../errors.zig").ZipponError;

pub const Self = @This();

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();

thread_arena: *std.heap.ThreadSafeAllocator,
thread_pool: *Pool,

pub fn init() ZipponError!Self {
    const thread_arena = allocator.create(std.heap.ThreadSafeAllocator) catch return ZipponError.MemoryError;
    thread_arena.* = std.heap.ThreadSafeAllocator{
        .child_allocator = allocator,
    };

    const thread_pool = allocator.create(Pool) catch return ZipponError.MemoryError;
    thread_pool.init(Pool.Options{
        .allocator = thread_arena.allocator(),
        .n_jobs = CPU_CORE,
    }) catch return ZipponError.ThreadError;

    return Self{
        .thread_pool = thread_pool,
        .thread_arena = thread_arena,
    };
}

pub fn deinit(self: *Self) void {
    self.thread_pool.deinit();
    arena.deinit();
}
