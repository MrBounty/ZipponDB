const std = @import("std");
const log = std.log.scoped(.thread);
const U64 = std.atomic.Value(u64);

// Remove the use waitgroup instead

pub const Self = @This();

processed_struct: U64 = U64.init(0),
error_file: U64 = U64.init(0),
completed_file: U64 = U64.init(0),
max_struct: u64,
max_file: u64,

pub fn init(max_struct: u64, max_file: u64) Self {
    return Self{
        .max_struct = max_struct,
        .max_file = max_file,
    };
}

pub fn isComplete(self: *Self) bool {
    return (self.completed_file.load(.acquire) + self.error_file.load(.acquire)) >= self.max_file;
}

pub fn completeThread(self: *Self) void {
    _ = self.completed_file.fetchAdd(1, .release);
}

pub fn incrementAndCheckStructLimit(self: *Self) bool {
    if (self.max_struct == 0) return false;
    const new_count = self.processed_struct.fetchAdd(1, .acquire);
    return (new_count + 1) >= self.max_struct;
}

pub fn checkStructLimit(self: *Self) bool {
    if (self.max_struct == 0) return false;
    const count = self.processed_struct.load(.acquire);
    return (count) >= self.max_struct;
}

pub fn logError(self: *Self, message: []const u8, err: anyerror) void {
    log.err("{s}: {any}", .{ message, err });
    _ = self.error_file.fetchAdd(1, .acquire);
}
