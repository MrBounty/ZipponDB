const std = @import("std");
const ZipponError = @import("errors.zig").ZipponError;
const config = @import("config");

const log = std.log.scoped(.utils);

// This use 2MB / 2048KB of memory
var map_error_buffer: [1024 * 1024]u8 = undefined; // This is for map AND error, not map of error and whatever
var value_buffer: [1024]u8 = undefined;
var path_buffer: [1024 * 1024]u8 = undefined;

var fa = std.heap.FixedBufferAllocator.init(&map_error_buffer);
const allocator = fa.allocator();

pub fn getEnvVariable(variable: []const u8) ?[]const u8 {
    fa.reset();

    var env_map = std.process.getEnvMap(allocator) catch return null;

    var iter = env_map.iterator();
    while (iter.next()) |entry| {
        if (std.mem.eql(u8, entry.key_ptr.*, variable)) return std.fmt.bufPrint(&value_buffer, "{s}", .{entry.value_ptr.*}) catch return null;
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

const stdout = std.io.getStdOut().writer();

// Maybe create a struct for that
pub fn send(comptime format: []const u8, args: anytype) void {
    if (config.DONT_SEND) return;

    stdout.print(format, args) catch |err| {
        log.err("Can't send: {any}", .{err});
        stdout.print("\x03\n", .{}) catch {};
    };

    stdout.print("\x03\n", .{}) catch {};
}

/// Print an error and send it to the user pointing to the token
pub fn printError(message: []const u8, err: ZipponError, query: ?[]const u8, start: ?usize, end: ?usize) ZipponError {
    if (config.DONT_SEND_ERROR) return err;
    fa.reset();

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    var writer = buffer.writer();

    writer.writeAll("{\"error\": \"") catch {};
    writer.writeAll("\n") catch {};
    writer.print("{s}\n", .{message}) catch {};

    if ((start != null) and (end != null) and (query != null)) {
        const query_buffer = std.fmt.bufPrint(&path_buffer, "{s}", .{query.?}) catch return ZipponError.MemoryError;
        std.mem.replaceScalar(u8, query_buffer, '\n', ' ');
        writer.print("{s}\n", .{query.?}) catch {};

        // Calculate the number of spaces needed to reach the start position.
        var spaces: usize = 0;
        while (spaces < start.?) : (spaces += 1) {
            writer.writeByte(' ') catch {};
        }

        // Print the '^' characters for the error span.
        var i: usize = start.?;
        while (i < end.?) : (i += 1) {
            writer.writeByte('^') catch {};
        }
        writer.writeAll("    \n") catch {}; // Align with the message
    }
    writer.writeAll("\"}") catch {};

    send("{s}", .{buffer.items});
    return err;
}

pub fn printOpenDir(comptime format: []const u8, args: anytype, options: std.fs.Dir.OpenDirOptions) ZipponError!std.fs.Dir {
    const path = std.fmt.bufPrint(&path_buffer, format, args) catch return ZipponError.CantOpenDir;
    return std.fs.cwd().openDir(path, options) catch ZipponError.CantOpenDir;
}

pub fn printOpenFile(comptime format: []const u8, args: anytype, options: std.fs.File.OpenFlags) ZipponError!std.fs.File {
    const path = std.fmt.bufPrint(&path_buffer, format, args) catch return ZipponError.CantOpenDir;
    return std.fs.cwd().openFile(path, options) catch ZipponError.CantOpenFile;
}
