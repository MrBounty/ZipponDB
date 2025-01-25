const std = @import("std");
const dtype = @import("dtype");
const DBEngine = @import("cli/core.zig");
const ZipponError = @import("error").ZipponError;

const names = [_][]const u8{ "Alice", "Bob", "Charlie", "Dave", "Eve" };
const emails = [_][]const u8{ "alice@email.com", "bob@email.com", "charlie@email.com", "dave@email.com", "eve@email.com" };
const dates = [_][]const u8{ "2000/01/01", "1954/04/02", "1998/01/21", "1977/12/31" };
const times = [_][]const u8{ "12:04", "20:45:11", "03:11:13", "03:00:01.0152" };
const datetimes = [_][]const u8{ "2000/01/01-12:04", "1954/04/02-20:45:11", "1998/01/21-03:11:13", "1977/12/31-03:00:01.0153" };
const ages = [_][]const u8{ "15", "11", "53", "34", "96", "64" };
const address = [_][]const u8{ "01 rue Notre Dame", "11 street St Bob", "Route to Heaven bis", "Here", "Not here", "Maybe here" };

pub const std_options = std.Options{
    .log_level = .info,
    .logFn = myLog,
};

const NUMBER_OF_RUN: usize = 10;
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
    const to_test = [_]usize{ 5_000, 100_000, 1_000_000, 10_000_000 };
    var line_buffer: [1024 * 1024]u8 = undefined;
    for (to_test) |users_count| {
        var db_engine = DBEngine.init(allocator, "benchmarkDB", "schema/benchmark");
        defer db_engine.deinit();

        // Empty db
        {
            var null_term_query_str = try std.fmt.bufPrintZ(&line_buffer, "DELETE User {{}}", .{});
            db_engine.runQuery(null_term_query_str);

            null_term_query_str = try std.fmt.bufPrintZ(&line_buffer, "DELETE Category {{}}", .{});
            db_engine.runQuery(null_term_query_str);

            null_term_query_str = try std.fmt.bufPrintZ(&line_buffer, "DELETE Item {{}}", .{});
            db_engine.runQuery(null_term_query_str);

            null_term_query_str = try std.fmt.bufPrintZ(&line_buffer, "DELETE Order {{}}", .{});
            db_engine.runQuery(null_term_query_str);
        }

        // Populate with random dummy value
        {
            std.debug.print("\n=====================================\n\n", .{});
            var prng = std.Random.DefaultPrng.init(0);
            const rng = prng.random();

            // Category
            {
                const null_term_query_str = try std.fmt.bufPrintZ(&line_buffer, "ADD Category (name = 'Book') ('Food') ('Toy') ('Other')", .{});
                db_engine.runQuery(null_term_query_str);
            }

            // Item
            {
                // TODO: Cache some filter. Here I end up parse Category everytime
                const null_term_query_str = try std.fmt.bufPrintZ(
                    &line_buffer, // I dont like 'category = {name='Book'}'. Maybe att a IS keyword ?
                    \\ADD Item
                    \\(name='Book1', price=12.45, category = {{name='Book'}})
                    \\(name='Book2', price=10.45, category = {{name='Book'}})
                    \\(name='Book3', price=12.45, category = {{name='Book'}})
                    \\(name='Book4', price=2.00, category = {{name='Book'}})
                    \\(name='Book5', price=59.99, category = {{name='Book'}})
                    \\(name='Book6', price=10.45, category = {{name='Book'}})
                    \\(name='Book7', price=10.45, category = {{name='Book'}})
                    \\
                    \\(name='Food1', price=1.45, category = {{name='Food'}})
                    \\(name='Food2', price=1.45, category = {{name='Food'}})
                    \\(name='Food3', price=1.45, category = {{name='Food'}})
                    \\(name='Food4', price=1.45, category = {{name='Food'}})
                    \\(name='Food6', price=1.45, category = {{name='Food'}})
                    \\(name='Food7', price=1.45, category = {{name='Food'}})
                    \\(name='Food8', price=1.45, category = {{name='Food'}})
                    \\
                    \\(name='Toy1', price=10.45, category = {{name='Toy'}})
                    \\(name='Toy2', price=4.45, category = {{name='Toy'}})
                    \\(name='Toy3', price=6.45, category = {{name='Toy'}})
                    \\(name='Toy4', price=1.45, category = {{name='Toy'}})
                    \\
                    \\(name='Other', price=0.99, category = {{name='Other'}})
                ,
                    .{},
                );
                db_engine.runQuery(null_term_query_str);
            }

            // User
            {
                std.debug.print("Populating with {d} users.\n", .{users_count});
                const populate_start_time = std.time.nanoTimestamp();

                var array = std.ArrayList(u8).init(allocator);
                defer array.deinit();
                var writer = array.writer();

                try writer.print(
                    "ADD User (name = '{s}', email='{s}', age={s}, address='{s}')",
                    .{
                        names[rng.uintAtMost(usize, names.len - 1)],
                        emails[rng.uintAtMost(usize, emails.len - 1)],
                        ages[rng.uintAtMost(usize, ages.len - 1)],
                        address[rng.uintAtMost(usize, address.len - 1)],
                    },
                );

                for (0..users_count - 1) |_| {
                    try writer.print(
                        "('{s}', '{s}', {s}, '{s}')",
                        .{
                            names[rng.uintAtMost(usize, names.len - 1)],
                            emails[rng.uintAtMost(usize, emails.len - 1)],
                            ages[rng.uintAtMost(usize, ages.len - 1)],
                            address[rng.uintAtMost(usize, address.len - 1)],
                        },
                    );
                }

                const null_term_query_str = try std.fmt.allocPrintZ(allocator, "{s}", .{array.items});
                defer allocator.free(null_term_query_str);

                db_engine.runQuery(null_term_query_str);

                const populate_end_time = std.time.nanoTimestamp();
                const populate_duration = @as(f64, @floatFromInt(populate_end_time - populate_start_time)) / 1e9;

                std.debug.print("Populate duration: {d:.6} seconds\n\n", .{populate_duration});
            }

            // Order
            if (false) {
                // Linked array not yet implemented and array manipulation not tested
                const null_term_query_str = try std.fmt.bufPrintZ(
                    &line_buffer, // I dont like 'category = {name='Book'}'. Maybe att a IS keyword ?
                    \\ADD Order (from={{}}, at=NOW, items={{name IN ['Food1', 'Food2']}}, quantity=[5 22])
                ,
                    .{},
                );
                db_engine.runQuery(null_term_query_str);
            }

            var buffer = std.ArrayList(u8).init(allocator);
            defer buffer.deinit();
            try db_engine.file_engine.writeDbMetrics(&buffer);
            std.debug.print("{s}\n", .{buffer.items});
            std.debug.print("--------------------------------------\n\n", .{});
        }

        if (false) {
            for (db_engine.schema_engine.struct_array) |sstruct| {
                const mb: f64 = @as(f64, @floatFromInt(sstruct.uuid_file_index.arena.queryCapacity())) / 1024.0 / 1024.0;
                std.debug.print("Sstruct: {s}\n", .{sstruct.name});
                std.debug.print("Memory: {d:.2}Mb\n", .{mb});
                std.debug.print("Count: {d}\n\n", .{sstruct.uuid_file_index.map.count()});
                std.debug.print("--------------------------------------\n\n", .{});
            }
        }

        // Run query
        {
            var read_time: f64 = 0;
            var read_write_time: f64 = 0;
            const queries = [_][]const u8{
                "GRAB User {}",
                "GRAB User {name='asd'}",
                "GRAB User [1] {}",
                "GRAB User [name] {}",
                "GRAB User {name = 'Charlie'}",
                "GRAB Category {}",
                "GRAB Item {}",
                "GRAB Order {}",
                "GRAB Order [from, items, quantity, at] {}",
                "DELETE User {}",
            };

            // Run benchmarks
            for (queries, 0..) |query, j| {
                var time_buff: [NUMBER_OF_RUN]f64 = undefined;
                for (0..NUMBER_OF_RUN) |i| {
                    const start_time = std.time.nanoTimestamp();

                    // Execute the query here
                    const null_term_query_str = try std.fmt.bufPrintZ(&line_buffer, "{s}", .{query});
                    db_engine.runQuery(null_term_query_str);

                    const end_time = std.time.nanoTimestamp();
                    time_buff[i] = @as(f64, @floatFromInt(end_time - start_time)) / 1e6;
                }
                std.debug.print(
                    "Query: \t{s}\nTime: \t{d:>6.2} ± {d:<6.2}ms | Min {d:>8.2}ms | Max {d:>8.2}ms\n\n",
                    .{ query, mean(time_buff), std_dev(time_buff), min(time_buff), max(time_buff) },
                );

                if (j == 0) read_write_time = mean(time_buff);
                if (j == 1) read_time = mean(time_buff);
            }
            std.debug.print(
                "Read: \t{d:.0} Entity/second\t*Include small condition\n",
                .{@as(f64, @floatFromInt(users_count)) / (read_time / 1000)},
            );
            std.debug.print(
                "Write: \t{d:.0} Entity/second\n",
                .{@as(f64, @floatFromInt(users_count)) / ((read_write_time - read_time) / 1000)},
            );
        }
    }
    std.debug.print("=====================================\n\n", .{});
}

fn min(array: [NUMBER_OF_RUN]f64) f64 {
    var current_min: f64 = 999999999999;
    for (array) |value| {
        if (value < current_min) current_min = value;
    }
    return current_min;
}

fn max(array: [NUMBER_OF_RUN]f64) f64 {
    var current_max: f64 = 0;
    for (array) |value| {
        if (value > current_max) current_max = value;
    }
    return current_max;
}

fn mean(array: [NUMBER_OF_RUN]f64) f64 {
    var total: f64 = 0;
    for (array) |value| {
        total += value;
    }
    return total / @as(f64, @floatFromInt(NUMBER_OF_RUN));
}

fn variance(array: [NUMBER_OF_RUN]f64) f64 {
    const m = mean(array);
    var square_diff: f64 = 0;
    for (array) |value| {
        square_diff += (value - m) * (value - m);
    }
    return square_diff / @as(f64, @floatFromInt(NUMBER_OF_RUN));
}

fn std_dev(array: [NUMBER_OF_RUN]f64) f64 {
    const vari = variance(array);
    return @sqrt(vari);
}
