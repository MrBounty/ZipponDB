// TODO: Put the ThreadSynx stuff and create a ThreadEngine with the arena, pool, and some methods

const std = @import("std");
const U64 = std.atomic.Value(u64);
const Pool = std.Thread.Pool;
const Allocator = std.mem.Allocator;

const ZipponError = @import("stuffs/errors.zig").ZipponError;
const CPU_CORE = @import("config.zig").CPU_CORE;
const BUFFER_SIZE = @import("config.zig").BUFFER_SIZE;
const log = std.log.scoped(.thread);

var alloc_buff: [BUFFER_SIZE]u8 = undefined;
var fa = std.heap.FixedBufferAllocator.init(&alloc_buff);
const allocator = fa.allocator();

pub const ThreadSyncContext = struct {
    processed_struct: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    error_file: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    completed_file: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    max_struct: u64,
    max_file: u64,

    pub fn init(max_struct: u64, max_file: u64) ThreadSyncContext {
        return ThreadSyncContext{
            .max_struct = max_struct,
            .max_file = max_file,
        };
    }

    pub fn isComplete(self: *ThreadSyncContext) bool {
        return (self.completed_file.load(.acquire) + self.error_file.load(.acquire)) >= self.max_file;
    }

    pub fn completeThread(self: *ThreadSyncContext) void {
        _ = self.completed_file.fetchAdd(1, .release);
    }

    pub fn incrementAndCheckStructLimit(self: *ThreadSyncContext) bool {
        if (self.max_struct == 0) return false;
        const new_count = self.processed_struct.fetchAdd(1, .monotonic);
        return (new_count + 1) >= self.max_struct;
    }

    pub fn checkStructLimit(self: *ThreadSyncContext) bool {
        if (self.max_struct == 0) return false;
        const count = self.processed_struct.load(.monotonic);
        return (count) >= self.max_struct;
    }

    pub fn logError(self: *ThreadSyncContext, message: []const u8, err: anyerror) void {
        log.err("{s}: {any}", .{ message, err });
        _ = self.error_file.fetchAdd(1, .acquire);
    }
};

pub const ThreadEngine = struct {
    thread_arena: *std.heap.ThreadSafeAllocator = undefined,
    thread_pool: *Pool = undefined,

    pub fn init() ThreadEngine {
        const thread_arena = allocator.create(std.heap.ThreadSafeAllocator) catch @panic("=(");
        thread_arena.* = std.heap.ThreadSafeAllocator{
            .child_allocator = allocator,
        };

        const thread_pool = allocator.create(Pool) catch @panic("=(");
        thread_pool.*.init(std.Thread.Pool.Options{
            .allocator = thread_arena.allocator(),
            .n_jobs = CPU_CORE,
        }) catch @panic("=(");

        return ThreadEngine{
            .thread_pool = thread_pool,
            .thread_arena = thread_arena,
        };
    }

    pub fn reset(_: ThreadEngine) void {
        fa.reset();
    }
};
