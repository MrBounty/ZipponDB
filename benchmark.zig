const std = @import("std");
const dtype = @import("dtype");
const DBEngine = @import("src/main.zig").DBEngine;
const ziqlTokenizer = @import("src/tokenizers/ziql.zig").Tokenizer;
const ziqlToken = @import("src/tokenizers/ziql.zig").Token;
const ziqlParser = @import("src/ziqlParser.zig").Parser;
const ZipponError = @import("src/stuffs/errors.zig").ZipponError;

const names = [_][]const u8{ "Alice", "Bob", "Charlie", "Dave", "Eve" };
const emails = [_][]const u8{ "alice@email.com", "bob@email.com", "charlie@email.com", "dave@email.com", "eve@email.com" };
const scores = [_]i32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };

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
    const to_test = [_]usize{ 1, 10, 100, 1_000, 10_000, 100_000, 1_000_000 };
    var line_buffer: [1024 * 1024]u8 = undefined;
    // Initialize your DBEngine here
    var db_engine = DBEngine.init("benchmark", "schema/example");
    defer db_engine.deinit();

    for (to_test) |users_count| {
        // Populate with random dummy value
        {
            std.debug.print("\n=====================================\n\n", .{});
            std.debug.print("Populating with {d} users.\n", .{users_count});

            var gpa = std.rand.DefaultPrng.init(0);
            const populate_start_time = std.time.nanoTimestamp();
            for (users_count) |_| {
                const name = names[gpa.random().uintAtMost(usize, names.len - 1)];
                const email = emails[gpa.random().uintAtMost(usize, emails.len - 1)];
                const age = gpa.random().uintAtMost(usize, 100);
                const score = scores[gpa.random().uintAtMost(usize, scores.len - 1)];
                const null_term_query_str = try std.fmt.bufPrintZ(
                    &line_buffer,
                    "ADD User (name = '{s}', email='{s}', age={d}, scores=[ {d} ], best_friend=none, friends=none, bday=2000/01/01, a_time=12:04, last_order=2000/01/01-12:45)",
                    .{ name, email, age, score },
                );
                var toker = ziqlTokenizer.init(null_term_query_str);
                var parser = ziqlParser.init(&toker, &db_engine.file_engine, &db_engine.schema_engine);
                try parser.parse();
            }
            const populate_end_time = std.time.nanoTimestamp();
            const populate_duration = @as(f64, @floatFromInt(populate_end_time - populate_start_time)) / 1e9;

            std.debug.print("Populate duration: {d:.6} seconds\n\n", .{populate_duration});

            var buffer = std.ArrayList(u8).init(std.heap.page_allocator);
            defer buffer.deinit();
            try db_engine.file_engine.writeDbMetrics(&buffer);
            std.debug.print("{s}\n", .{buffer.items});
            std.debug.print("--------------------------------------\n\n", .{});
        }

        // Define your benchmark queries
        {
            const queries = [_][]const u8{
                "GRAB User {}",
                "GRAB User [1] {}",
                "GRAB User [name] {}",
                "GRAB User {name = 'Charlie'}",
                "GRAB User {age > 30}",
                "DELETE User {}",
            };

            // Run benchmarks
            for (queries) |query| {
                const start_time = std.time.nanoTimestamp();

                // Execute the query here
                const null_term_query_str = try std.fmt.bufPrintZ(&line_buffer, "{s}", .{query});
                var toker = ziqlTokenizer.init(null_term_query_str);
                var parser = ziqlParser.init(&toker, &db_engine.file_engine, &db_engine.schema_engine);
                try parser.parse();

                const end_time = std.time.nanoTimestamp();
                const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1e9;

                std.debug.print("Query: \t\t{s}\nDuration: \t{d:.6} seconds\n\n", .{ query, duration });
            }

            std.debug.print("=====================================\n\n", .{});
        }
    }
}
