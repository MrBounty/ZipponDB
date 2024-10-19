const std = @import("std");
const ZipponError = @import("errors.zig").ZipponError;

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

pub fn getArgsString(allocator: std.mem.Allocator) std.ArrayList(u8) {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var buffer = std.ArrayList(u8).init(allocator);
    var writer = buffer.writer();

    for (args) |arg| {
        writer.print("{s} ", .{arg});
    }

    buffer.append(0);

    return buffer;
}

const stdout = std.io.getStdOut().writer();

// Maybe create a struct for that
pub fn send(comptime format: []const u8, args: anytype) void {
    stdout.print(format, args) catch |err| {
        std.log.err("Can't send: {any}", .{err});
        stdout.print("\x03\n", .{}) catch {};
    };

    stdout.print("\x03\n", .{}) catch {};
}

/// Print an error and send it to the user pointing to the token
pub fn printError(message: []const u8, err: ZipponError, query: ?[]const u8, start: ?usize, end: ?usize) ZipponError {
    const allocator = std.heap.page_allocator;
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    var writer = buffer.writer();

    writer.print("\n", .{}) catch {}; // Maybe use write all, not sure if it affect performance in any considerable way
    writer.print("{s}\n", .{message}) catch {};

    if ((start != null) and (end != null) and (query != null)) {
        const buffer_query = allocator.dupe(u8, query.?) catch return ZipponError.MemoryError;
        defer allocator.free(buffer_query);

        std.mem.replaceScalar(u8, buffer_query, '\n', ' ');
        writer.print("{s}\n", .{buffer_query}) catch {};

        // Calculate the number of spaces needed to reach the start position.
        var spaces: usize = 0;
        while (spaces < start.?) : (spaces += 1) {
            writer.print(" ", .{}) catch {};
        }

        // Print the '^' characters for the error span.
        var i: usize = start.?;
        while (i < end.?) : (i += 1) {
            writer.print("^", .{}) catch {};
        }
        writer.print("    \n", .{}) catch {}; // Align with the message
    }

    send("{s}", .{buffer.items});
    return err;
}
