const std = @import("std");
const dtype = @import("dtype");
const DBEngine = @import("src/cli/core.zig");
const ZipponError = @import("error").ZipponError;

const names = [_][]const u8{ "Alice", "Bob", "Charlie", "Dave", "Eve" };
const emails = [_][]const u8{ "alice@email.com", "bob@email.com", "charlie@email.com", "dave@email.com", "eve@email.com" };
const dates = [_][]const u8{ "2000/01/01", "1954/04/02", "1998/01/21", "1977/12/31" };
const times = [_][]const u8{ "12:04", "20:45:11", "03:11:13", "03:00:01.0152" };
const datetimes = [_][]const u8{ "2000/01/01-12:04", "1954/04/02-20:45:11", "1998/01/21-03:11:13", "1977/12/31-03:00:01.0153" };
const scores = [_]i32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };

pub const std_options = std.Options{
    .log_level = .info,
    .logFn = myLog,
};

var date_buffer: [64]u8 = undefined;
var date_fa = std.heap.FixedBufferAllocator.init(&date_buffer);
const date_allocator = date_fa.allocator();

pub fn myLog(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime message_level.asText();
    const prefix = if (scope == .default) " - " else "(" ++ @tagName(scope) ++ ") - ";

    const potential_file: ?std.fs.File = std.fs.cwd().openFile("benchmarkDB/LOG/log", .{ .mode = .write_only }) catch null;

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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const deinit_status = gpa.deinit();
        switch (deinit_status) {
            .leak => @panic("Oupsy"),
            .ok => {},
        }
    }

    try benchmark(gpa.allocator());
}

test "benchmark" {
    const allocator = std.testing.allocator;
    try benchmark(allocator);
}

// Maybe I can make it a test to use the testing alloc
pub fn benchmark(allocator: std.mem.Allocator) !void {
    const to_test = [_]usize{ 5, 50, 500, 5_000, 50_000, 500_000, 5_000_000 };
    var line_buffer: [1024 * 1024]u8 = undefined;
    for (to_test) |users_count| {
        var db_engine = DBEngine.init(allocator, "benchmarkDB", "schema/benchmark");
        defer db_engine.deinit();

        // Empty db
        {
            const null_term_query_str = try std.fmt.bufPrintZ(&line_buffer, "DELETE User {{}}", .{});
            db_engine.runQuery(null_term_query_str);
        }

        // Populate with random dummy value
        {
            std.debug.print("\n=====================================\n\n", .{});
            std.debug.print("Populating with {d} users.\n", .{users_count});

            var prng = std.Random.DefaultPrng.init(0);
            const rng = prng.random();
            const populate_start_time = std.time.nanoTimestamp();

            var array = std.ArrayList(u8).init(allocator);
            defer array.deinit();
            var writer = array.writer();

            try writer.print(
                "ADD User (name = '{s}', email='{s}', orders=none)",
                .{
                    names[rng.uintAtMost(usize, names.len - 1)],
                    emails[rng.uintAtMost(usize, emails.len - 1)],
                },
            );

            for (0..users_count - 1) |_| {
                try writer.print(
                    "('{s}', '{s}', none)",
                    .{
                        names[rng.uintAtMost(usize, names.len - 1)],
                        emails[rng.uintAtMost(usize, emails.len - 1)],
                    },
                );
            }

            const null_term_query_str = try std.fmt.allocPrintZ(allocator, "{s}", .{array.items});
            defer allocator.free(null_term_query_str);

            db_engine.runQuery(null_term_query_str);

            const populate_end_time = std.time.nanoTimestamp();
            const populate_duration = @as(f64, @floatFromInt(populate_end_time - populate_start_time)) / 1e9;

            std.debug.print("Populate duration: {d:.6} seconds\n\n", .{populate_duration});

            var buffer = std.ArrayList(u8).init(allocator);
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

        // Run query
        {
            const queries = [_][]const u8{
                "GRAB User {}",
                "GRAB User {name='asd'}",
                "GRAB User [1] {}",
                "GRAB User [name] {}",
                "GRAB User {name = 'Charlie'}",
                "DELETE User {}",
            };

            // Run benchmarks
            for (queries) |query| {
                const start_time = std.time.nanoTimestamp();

                // Execute the query here
                const null_term_query_str = try std.fmt.bufPrintZ(&line_buffer, "{s}", .{query});
                db_engine.runQuery(null_term_query_str);

                const end_time = std.time.nanoTimestamp();
                const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1e6;

                std.debug.print("Query: \t\t{s}\nDuration: \t{d:.6} ms\n\n", .{ query, duration });
            }
        }
    }
    std.debug.print("=====================================\n\n", .{});
}
