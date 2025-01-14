const std = @import("std");
const dtype = @import("dtype");
const DBEngine = @import("src/cli/core.zig");
const ziqlParser = @import("src/ziql/core.zig");
const ZipponError = @import("error").ZipponError;

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
    const to_test = [_]usize{ 500, 50_000, 5_000_000 };
    var line_buffer: [1024 * 1024]u8 = undefined;
    for (to_test) |users_count| {
        var db_engine = DBEngine.init("benchmarkDB", "schema/benchmark");
        defer db_engine.deinit();

        {
            const null_term_query_str = try std.fmt.bufPrintZ(&line_buffer, "DELETE User {{}}", .{});
            var parser = ziqlParser.init(&db_engine.file_engine, &db_engine.schema_engine);
            try parser.parse(null_term_query_str);
        }
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
                "ADD User (name = '{s}', email='{s}')",
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

            var parser = ziqlParser.init(&db_engine.file_engine, &db_engine.schema_engine);
            try parser.parse(null_term_query_str);

            const populate_end_time = std.time.nanoTimestamp();
            const populate_duration = @as(f64, @floatFromInt(populate_end_time - populate_start_time)) / 1e9;

            std.debug.print("Populate duration: {d:.6} seconds\n\n", .{populate_duration});

            var buffer = std.ArrayList(u8).init(std.heap.page_allocator);
            defer buffer.deinit();
            try db_engine.file_engine.writeDbMetrics(&buffer);
            std.debug.print("{s}\n", .{buffer.items});
            std.debug.print("--------------------------------------\n\n", .{});
        }

        //{
        //    for (db_engine.schema_engine.struct_array) |sstruct| {
        //        const mb: f64 = @as(f64, @floatFromInt(sstruct.uuid_file_index.arena.queryCapacity())) / 1024.0 / 1024.0;
        //        std.debug.print("Sstruct: {s}\n", .{sstruct.name});
        //        std.debug.print("Memory: {d:.2}Mb\n", .{mb});
        //        std.debug.print("Count: {d}\n\n", .{sstruct.uuid_file_index.map.count()});
        //        std.debug.print("--------------------------------------\n\n", .{});
        //    }
        //}

        // Define your benchmark queries
        {
            const queries = [_][]const u8{
                "GRAB User {}",
                "GRAB User [1] {}",
                "GRAB User [name] {}",
                "GRAB User {name = 'Charlie'}",
                "GRAB User {age > 30}",
                "GRAB User {bday > 2000/01/01}",
                "GRAB User {age > 30 AND name = 'Charlie' AND bday > 2000/01/01}",
                "GRAB User {best_friend IN {name = 'Charlie'}}",
                "DELETE User {}",
            };

            // Run benchmarks
            for (queries) |query| {
                const start_time = std.time.nanoTimestamp();

                // Execute the query here
                const null_term_query_str = try std.fmt.bufPrintZ(&line_buffer, "{s}", .{query});
                var parser = ziqlParser.init(&db_engine.file_engine, &db_engine.schema_engine);
                try parser.parse(null_term_query_str);

                const end_time = std.time.nanoTimestamp();
                const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1e6;

                std.debug.print("Query: \t\t{s}\nDuration: \t{d:.6} ms\n\n", .{ query, duration });
            }

            std.debug.print("=====================================\n\n", .{});
        }
    }
}
