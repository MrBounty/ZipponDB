const std = @import("std");

pub fn getEnvVariables(allocator: std.mem.Allocator, variable: []const u8) ?[]const u8 {
    var env_map = std.process.getEnvMap(allocator) catch return null;
    defer env_map.deinit();

    var iter = env_map.iterator();

    while (iter.next()) |entry| {
        if (std.mem.eql(u8, entry.key_ptr.*, variable)) return allocator.dupe(u8, entry.value_ptr.*) catch return null;
    }

    return null;
}
