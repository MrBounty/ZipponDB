const std = @import("std");
const U64 = std.atomic.Value(u64);
const Pool = std.Thread.Pool;

const ZipponError = @import("error").ZipponError;
const CPU_CORE = @import("config").CPU_CORE;
const log = std.log.scoped(.thread);

pub const ThreadEngine = @This();

allocator: std.mem.Allocator,
thread_arena: *std.heap.ThreadSafeAllocator,
thread_pool: *Pool,

pub fn init(allocator: std.mem.Allocator) !ThreadEngine {
    log.debug("ThreadEngine Initializing.", .{});
    const thread_arena = try allocator.create(std.heap.ThreadSafeAllocator);
    thread_arena.* = std.heap.ThreadSafeAllocator{
        .child_allocator = allocator,
    };

    const cpu_core = if (CPU_CORE == 0) std.Thread.getCpuCount() catch 1 else CPU_CORE;
    log.debug("  Using {d} cpu core.", .{cpu_core});
    log.debug("  Using {d}Mb stack size.", .{std.Thread.SpawnConfig.default_stack_size / 1024 / 1024});

    const thread_pool = try allocator.create(std.Thread.Pool);
    try thread_pool.init(std.Thread.Pool.Options{
        .allocator = thread_arena.allocator(),
        .n_jobs = cpu_core,
    });

    return ThreadEngine{
        .allocator = allocator,
        .thread_pool = thread_pool,
        .thread_arena = thread_arena,
    };
}

pub fn deinit(self: *ThreadEngine) void {
    log.debug("Deinit ThreadEngine.", .{});
    self.thread_pool.deinit();
    self.allocator.destroy(self.thread_arena);
    self.allocator.destroy(self.thread_pool);
}

// Not tested, for later when config is runtime
pub fn setCpuCore(self: *ThreadEngine, cpu_core: usize) void {
    log.debug("Set CPU count to {d}.", .{cpu_core});
    self.thread_pool.deinit();
    self.thread_pool.init(std.Thread.Pool.Options{
        .allocator = self.allocator,
        .n_jobs = cpu_core,
    });
}
