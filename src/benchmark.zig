const std = @import("std");
const DBEngine = @import("main.zig").DBEngine;
const dtype = @import("dtype");
const ziqlTokenizer = @import("tokenizers/ziql.zig").Tokenizer;
const ziqlToken = @import("tokenizers/ziql.zig").Token;
const ziqlParser = @import("ziqlParser.zig").Parser;

pub const std_options = .{
    .logFn = myLog,
};

pub fn myLog(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    if (true) return;
    _ = message_level;
    _ = scope;
    _ = format;
    _ = args;
}

pub fn main() !void {
    var line_buffer: [1024 * 1024]u8 = undefined;
    // Initialize your DBEngine here
    var db_engine = DBEngine.init("benchmark", "example.zipponschema");
    defer db_engine.deinit();

    // Define your benchmark queries
    const populate = [_][]const u8{
        "ADD User (name = 'Bob', email='bob@email.com', age=55, scores=[ 1 ], best_friend=none, friends=none, bday=2000/01/01, a_time=12:04, last_order=2000/01/01-12:45)",
    };

    // Run benchmarks
    const populate_start_time = std.time.nanoTimestamp();
    for (populate) |query| {
        const null_term_query_str = try std.fmt.bufPrintZ(&line_buffer, "{s}", .{query});
        for (0..1) |_| {
            var toker = ziqlTokenizer.init(null_term_query_str);
            var parser = ziqlParser.init(&toker, &db_engine.file_engine, &db_engine.schema_engine);
            try parser.parse();
        }
    }

    const populate_end_time = std.time.nanoTimestamp();
    const populate_duration = @as(f64, @floatFromInt(populate_end_time - populate_start_time)) / 1e9;

    std.debug.print("Populate duration: {d:.6} seconds\n\n", .{populate_duration});

    // Define your benchmark queries
    const queries = [_][]const u8{
        "GRAB User {}",
        "GRAB User [1] {}",
        "GRAB User [name] {}",
        "GRAB User {name = 'Adrien'}",
        "GRAB User {age > 30}",
    };

    // Run benchmarks
    std.debug.print("Running benchmarks...\n", .{});
    for (queries) |query| {
        const start_time = std.time.nanoTimestamp();

        // Execute the query here
        const null_term_query_str = try std.fmt.bufPrintZ(&line_buffer, "{s}", .{query});
        var toker = ziqlTokenizer.init(null_term_query_str);
        var parser = ziqlParser.init(&toker, &db_engine.file_engine, &db_engine.schema_engine);
        try parser.parse();

        const end_time = std.time.nanoTimestamp();
        const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1e9;

        std.debug.print("Query: {s}\nDuration: {d:.6} seconds\n\n", .{ query, duration });
    }
}
