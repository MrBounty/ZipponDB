const std = @import("std");
const Allocator = std.mem.Allocator;
const cliTokenizer = @import("tokenizers/cli.zig").Tokenizer;
const cliToken = @import("tokenizers/cli.zig").Token;
const ziqlTokenizer = @import("tokenizers/ziql.zig").Tokenizer;
const ziqlToken = @import("tokenizers/ziql.zig").Token;
const ziqlParser = @import("ziqlParser.zig").Parser;

const stdout = std.io.getStdOut().writer();

pub fn main() !void {
    // TODO: Use an environment variable for the path of the DB
    checkAndCreateDirectories();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    defer {
        switch (gpa.deinit()) {
            .ok => std.debug.print("No memory leak baby !\n", .{}),
            .leak => {
                std.debug.print("We fucked it up bro...\n", .{});
                @panic("=(");
            },
        }
    }

    const line_buf = try allocator.alloc(u8, 1024 * 50);
    defer allocator.free(line_buf);

    while (true) {
        std.debug.print("> ", .{});
        const line = try std.io.getStdIn().reader().readUntilDelimiterOrEof(line_buf, '\n');

        if (line) |line_str| {
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
                        .keyword_help => std.debug.print("The run command will take a ZiQL query between \" and run it. eg: run \"GRAB User\"\n"),
                        else => std.debug.print("After command run, need a string of a query, eg: \"GRAB User\"\n", .{}),
                    }
                },
                .keyword_schema => {
                    const second_token = cliToker.next();

                    switch (second_token.tag) {
                        .keyword_describe => try runCommand("__DESCRIBE__"),
                        .keyword_build => std.debug.print("Need to do the SchemaEngine tu update and migrate the schema"),
                        .keyword_help => {
                            std.debug.print("{s}", .{
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
                    std.debug.print("{s}", .{
                        \\Welcome to ZipponDB!
                        \\
                        \\run       To run a query. Args => query: str, the query to execute.
                        \\schema    Build a new engine and print current schema.
                        \\kill      To stop the process without saving
                        \\save      Save the database to the normal files.
                        \\dump      Create a new folder with all data as copy. Args => foldername: str, the name of the folder.
                        \\bump      Replace current data with a previous dump. Args => foldername: str, the name of the folder.
                        \\
                    });
                },
                .keyword_quit => break,
                .eof => {},
                else => std.debug.print("Command need to start with a keyword, including: run, schema, help and quit\n", .{}),
            }
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

    cwd.makeDir("ZipponDB/ENGINE") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => @panic("Error other than path already exists when trying to create the ENGINE directory.\n"),
    };
}
