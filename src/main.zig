const std = @import("std");
const utils = @import("utils.zig");
const config = @import("config");
const Cli = @import("cli/core.zig");

const ZipponError = @import("error").ZipponError;

var log_buff: [1024]u8 = undefined;
var log_path: []const u8 = undefined;
var date_buffer: [64]u8 = undefined;
var date_fa = std.heap.FixedBufferAllocator.init(&date_buffer);
const date_allocator = date_fa.allocator();

pub const std_options = .{
    .logFn = myLog,
};

pub fn myLog(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime message_level.asText();
    const prefix = if (scope == .default) " - " else "(" ++ @tagName(scope) ++ ") - ";

    const potential_file: ?std.fs.File = std.fs.cwd().openFile(log_path, .{ .mode = .write_only }) catch null;

    if (potential_file) |file| {
        date_fa.reset();
        const now = @import("dtype").DateTime.now();
        var date_format_buffer = std.ArrayList(u8).init(date_allocator);
        defer date_format_buffer.deinit();
        now.format("YYYY/MM/DD-HH:mm:ss.SSSS", date_format_buffer.writer()) catch return;

        file.seekFromEnd(0) catch return;
        const writer = file.writer();

        writer.print("{s}{s}Time: {s} - ", .{ level_txt, prefix, date_format_buffer.items }) catch return;
        writer.print(format, args) catch return;
        writer.writeByte('\n') catch return;
        file.close();
    }
}

pub fn setLogPath(path: []const u8) void {
    log_path = std.fmt.bufPrint(&log_buff, "{s}/LOG/log", .{path}) catch return;
}

pub fn main() !void {
    var cli = Cli.init(null, null);
    defer cli.deinit();

    try cli.start();
}
