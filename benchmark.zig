const std = @import("std");
const dtype = @import("dtype");
const DBEngine = @import("src/main.zig").DBEngine;
const ziqlTokenizer = @import("src/tokenizers/ziql.zig").Tokenizer;
const ziqlToken = @import("src/tokenizers/ziql.zig").Token;
const ziqlParser = @import("src/ziqlParser.zig").Parser;
const ZipponError = @import("src/stuffs/errors.zig").ZipponError;

const names = [_][]const u8{ "Alice", "Bob", "Charlie", "Dave", "Eve" };
const emails = [_][]const u8{ "alice@email.com", "bob@email.com", "charlie@email.com", "dave@email.com", "eve@email.com" };
const dates = [_][]const u8{ "2000/01/01", "1954/04/02", "1998/01/21", "1977/12/31" };
const times = [_][]const u8{ "12:04", "20:45:11", "03:11:13", "03:00:01.0152" };
const datetimes = [_][]const u8{ "2000/01/01-12:04", "1954/04/02-20:45:11", "1998/01/21-03:11:13", "1977/12/31-03:00:01.0153" };
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
    const to_test = [_]usize{50_000};
    var line_buffer: [1024 * 1024]u8 = undefined;
    var db_engine = DBEngine.init("benchmark", "schema/example");
    defer db_engine.deinit();

    for (to_test) |users_count| {
        // Populate with random dummy value
        // Need some speed up, spended times to find that it is the parsonConditionValue that take time, the last switch to be exact, that parse str to value
        {
            std.debug.print("\n=====================================\n\n", .{});
            std.debug.print("Populating with {d} users.\n", .{users_count});

            const allocator = std.heap.page_allocator;

            var prng = std.rand.DefaultPrng.init(0);
            const rng = prng.random();
            const populate_start_time = std.time.nanoTimestamp();

            var array = std.ArrayList(u8).init(allocator);
            defer array.deinit();
            var writer = array.writer();

            try writer.print(
                "ADD User (name = '{s}', email='{s}', age={d}, scores=[ {d} ], best_friend=none, friends=none, bday={s}, a_time={s}, last_order={s})",
                .{
                    names[rng.uintAtMost(usize, names.len - 1)],
                    emails[rng.uintAtMost(usize, emails.len - 1)],
                    rng.uintAtMost(usize, 100),
                    scores[rng.uintAtMost(usize, scores.len - 1)],
                    dates[rng.uintAtMost(usize, dates.len - 1)],
                    times[rng.uintAtMost(usize, times.len - 1)],
                    datetimes[rng.uintAtMost(usize, datetimes.len - 1)],
                },
            );

            for (users_count - 1) |_| {
                try writer.print(
                    "('{s}', '{s}', {d}, [ {d} ], none, none, {s}, {s}, {s})",
                    .{
                        names[rng.uintAtMost(usize, names.len - 1)],
                        emails[rng.uintAtMost(usize, emails.len - 1)],
                        rng.uintAtMost(usize, 100),
                        scores[rng.uintAtMost(usize, scores.len - 1)],
                        dates[rng.uintAtMost(usize, dates.len - 1)],
                        times[rng.uintAtMost(usize, times.len - 1)],
                        datetimes[rng.uintAtMost(usize, datetimes.len - 1)],
                    },
                );
            }

            const null_term_query_str = try std.fmt.allocPrintZ(allocator, "{s}", .{array.items});
            defer allocator.free(null_term_query_str);

            var toker = ziqlTokenizer.init(null_term_query_str);
            var parser = ziqlParser.init(&toker, &db_engine.file_engine, &db_engine.schema_engine);
            try parser.parse();

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
                "GRAB User {bday > 2000/01/01}",
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
