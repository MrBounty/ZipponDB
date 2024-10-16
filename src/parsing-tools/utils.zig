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

pub fn getDirTotalSize(dir: std.fs.Dir) !u64 {
    var total: u64 = 0;
    var stat: std.fs.File.Stat = undefined;
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .directory) {
            const sub_dir = try dir.openDir(entry.name, .{ .iterate = true });
            total += try getDirTotalSize(sub_dir);
        }

        if (entry.kind != .file) continue;
        stat = try dir.statFile(entry.name);
        total += stat.size;
    }
    return total;
}
