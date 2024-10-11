const std = @import("std");
const Allocator = std.mem.Allocator;
const FileEngine = @import("fileEngine.zig").FileEngine;
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

const State = enum {
    expect_main_command,
    expect_query,
    expect_schema_command,
    expect_path_to_schema,
    quit,
    end,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        switch (gpa.deinit()) {
            .ok => std.log.debug("No memory leak baby !\n", .{}),
            .leak => std.log.debug("We fucked it up bro...\n", .{}),
        }
    }

    // TODO: Use the path of an environment variable if one found, otherwise wait for the user to use the schema init
    checkAndCreateDirectories();
    var file_engine = FileEngine.init(allocator, null);
    defer file_engine.deinit();

    const line_buf = try allocator.alloc(u8, 1024 * 50);
    defer allocator.free(line_buf);

    var state: State = .expect_main_command;

    // TODO: Use a State to prevent first_token and second_token
    while (true) {
        std.debug.print("> ", .{});
        const line = try std.io.getStdIn().reader().readUntilDelimiterOrEof(line_buf, '\n');

        if (line) |line_str| {
            const time_initial = std.time.microTimestamp();

            const null_term_line_str = try allocator.dupeZ(u8, line_str[0..line_str.len]);
            defer allocator.free(null_term_line_str);

            var cliToker = cliTokenizer.init(null_term_line_str);
            var token = cliToker.next();
            state = .expect_main_command;

            while ((state != .end) and (state != .quit)) : (token = cliToker.next()) {
                switch (state) {
                    .expect_main_command => switch (token.tag) {
                        .keyword_run => state = .expect_query,
                        .keyword_schema => state = .expect_schema_command,
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
                            state = .end;
                        },
                        .keyword_quit => state = .quit,
                        .eof => state = .end,
                        else => {
                            send("Command need to start with a keyword, including: run, schema, help and quit\n", .{});
                            state = .end;
                        },
                    },

                    .expect_query => switch (token.tag) {
                        .string_literal => {
                            const null_term_query_str = try allocator.dupeZ(u8, line_str[token.loc.start + 1 .. token.loc.end - 1]);
                            defer allocator.free(null_term_query_str);
                            try runQuery(null_term_query_str, &file_engine);
                            state = .end;
                        },
                        .keyword_help => {
                            send("The run command will take a ZiQL query between \" and run it. eg: run \"GRAB User\"\n", .{});
                            state = .end;
                        },
                        else => {
                            send("After command run, need a string of a query, eg: \"GRAB User\"\n", .{});
                            state = .end;
                        },
                    },

                    .expect_schema_command => switch (token.tag) {
                        .keyword_describe => {
                            if (file_engine.null_terminated_schema_buff.len == 0) {
                                send("Need to init the schema first. Please use the schema init path/to/schema command to start.", .{});
                            } else {
                                send("Schema:\n {s}", .{file_engine.null_terminated_schema_buff});
                            }
                            state = .end;
                        },
                        .keyword_init => state = .expect_path_to_schema,
                        .keyword_help => {
                            send("{s}", .{
                                \\Here are all available options to use with the schema command:
                                \\
                                \\describe  Print the schema use by the current engine.
                                \\build     Build a new engine using a schema file. Args => filename: str, path of schema file to use. Default 'schema.zipponschema'.
                                \\
                            });
                            state = .end;
                        },
                        else => {
                            std.debug.print("schema available options: describe, build & help\n", .{});
                            state = .end;
                        },
                    },

                    .expect_path_to_schema => switch (token.tag) {
                        .identifier => {
                            file_engine.initDataFolder(cliToker.getTokenSlice(token)) catch |err| switch (err) {
                                error.SchemaFileNotFound => {
                                    send("Coulnt find the schema file at {s}", .{cliToker.getTokenSlice(token)});
                                    state = .end;
                                },
                                else => {
                                    send("Error initializing the schema", .{});
                                    state = .end;
                                },
                            };
                            send("Successfully initialized the database!", .{});
                            state = .end;
                        },
                        else => {
                            send("Expected a path to a schema file after the schema init command.", .{});
                            state = .end;
                        },
                    },

                    .quit, .end => break,
                }
            }

            const time_final = std.time.microTimestamp();
            const duration = time_final - time_initial;
            std.debug.print("Time: {d:.2}ms\n", .{@as(f64, @floatFromInt(duration)) / 1000.0});

            if (state == .quit) break;
        }
    }
}

pub fn runQuery(null_term_query_str: [:0]const u8, file_engine: *FileEngine) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var toker = ziqlTokenizer.init(null_term_query_str);

    var parser = ziqlParser.init(allocator, &toker, file_engine);
    defer {
        parser.deinit();
        switch (gpa.deinit()) {
            .ok => std.log.debug("No memory leak baby !\n", .{}),
            .leak => std.log.debug("We fucked it up bro...\n", .{}),
        }
    }

    try parser.parse();
}

// TODO: Put that in the FileEngine
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
