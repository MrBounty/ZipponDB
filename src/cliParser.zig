const std = @import("std");
const Allocator = std.mem.Allocator;
const DataEngine = @import("engines/file.zig").FileEngine;
const cliTokenizer = @import("tokenizers/cli.zig").Tokenizer;
const cliToken = @import("tokenizers/cli.zig").Token;
const ziqlTokenizer = @import("tokenizers/ziql.zig").Tokenizer;
const ziqlToken = @import("tokenizers/ziql.zig").Token;
const ziqlParser = @import("ziqlParser.zig").Parser;

const stdout = std.io.getStdOut().writer();

fn send(comptime format: []const u8, args: anytype) void {
    stdout.print(format, args) catch |err| {
        std.log.err("Can't send: {any}", .{err});
        stdout.print("\x03\n", .{}) catch {};
    };

    stdout.print("\x03\n", .{}) catch {};
}

pub fn main() !void {
    // TODO: Use an environment variable for the path of the DB
    checkAndCreateDirectories();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    defer {
        switch (gpa.deinit()) {
            .ok => std.log.debug("No memory leak baby !\n", .{}),
            .leak => std.log.debug("We fucked it up bro...\n", .{}),
        }
    }

    const line_buf = try allocator.alloc(u8, 1024 * 50);
    defer allocator.free(line_buf);

    // TODO: Use a State to prevent first_token and second_token
    while (true) {
        std.debug.print("> ", .{});
        const line = try std.io.getStdIn().reader().readUntilDelimiterOrEof(line_buf, '\n');

        if (line) |line_str| {
            const time_initial = std.time.microTimestamp();

            const null_term_line_str = try allocator.dupeZ(u8, line_str[0..line_str.len]);
            defer allocator.free(null_term_line_str);

            var cliToker = cliTokenizer.init(null_term_line_str);
            const command_token = cliToker.next();
            switch (command_token.tag) {
                .keyword_run => {
                    const query_token = cliToker.next();
                    switch (query_token.tag) {
                        .string_literal => {
                            const null_term_query_str = try allocator.dupeZ(u8, line_str[query_token.loc.start + 1 .. query_token.loc.end - 1]);
                            defer allocator.free(null_term_query_str);
                            try runCommand(null_term_query_str);
                        },
                        .keyword_help => send("The run command will take a ZiQL query between \" and run it. eg: run \"GRAB User\"\n", .{}),
                        else => send("After command run, need a string of a query, eg: \"GRAB User\"\n", .{}),
                    }
                },
                .keyword_schema => {
                    const second_token = cliToker.next();

                    switch (second_token.tag) {
                        .keyword_describe => send("{s}\n", .{ // TODO: Change that to use the SchemaEngine
                            \\User (
                            \\  name: str,
                            \\  email: str,
                            \\)
                            \\Message (
                            \\  content: str,
                            \\)
                        }),
                        .keyword_init => { // Maybe rename that in init now that I dont build binary anymore
                            const data_engine = DataEngine.init(allocator, null);
                            try data_engine.initDataFolder();
                        },
                        .keyword_help => {
                            send("{s}", .{
                                \\Here are all available options to use with the schema command:
                                \\
                                \\describe  Print the schema use by the current engine.
                                \\build     Build a new engine using a schema file. Args => filename: str, path of schema file to use. Default 'schema.zipponschema'.
                                \\
                            });
                        },
                        else => std.debug.print("schema available options: describe, build & help\n", .{}),
                    }
                },
                .keyword_help => {
                    send("{s}", .{
                        \\Welcome to ZipponDB!
                        \\
                        \\run       To run a query. Args => query: str, the query to execute.
                        \\schema    Build a new engine and print current schema.
                        \\quit      To stop the process without saving
                        \\dump      Create a new folder with all data as copy. Args => foldername: str, the name of the folder.
                        \\bump      Replace current data with a previous dump. Args => foldername: str, the name of the folder.
                        \\
                    });
                },
                .keyword_quit => break,
                .eof => {},
                else => send("Command need to start with a keyword, including: run, schema, help and quit\n", .{}),
            }

            const time_final = std.time.microTimestamp();
            const duration = time_final - time_initial;
            std.debug.print("Time: {d:.2}ms\n", .{@as(f64, @floatFromInt(duration)) / 1000.0});
        }
    }
}

pub fn runCommand(null_term_query_str: [:0]const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var toker = ziqlTokenizer.init(null_term_query_str);

    var parser = ziqlParser.init(allocator, &toker);
    defer parser.deinit();

    try parser.parse();
}

fn checkAndCreateDirectories() void {
    const cwd = std.fs.cwd();

    cwd.makeDir("ZipponDB") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => @panic("Error other than path already exists when trying to create the ZipponDB directory.\n"),
    };

    cwd.makeDir("ZipponDB/DATA") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => @panic("Error other than path already exists when trying to create the DATA directory.\n"),
    };

    cwd.makeDir("ZipponDB/BACKUP") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => @panic("Error other than path already exists when trying to create the ENGINE directory.\n"),
    };

    cwd.makeDir("ZipponDB/LOG") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => @panic("Error other than path already exists when trying to create the ENGINE directory.\n"),
    };
}
