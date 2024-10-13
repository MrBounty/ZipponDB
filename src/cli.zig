const std = @import("std");
const Allocator = std.mem.Allocator;
const FileEngine = @import("fileEngine.zig").FileEngine;
const cliTokenizer = @import("tokenizers/cli.zig").Tokenizer;
const cliToken = @import("tokenizers/cli.zig").Token;
const ziqlTokenizer = @import("tokenizers/ziql.zig").Tokenizer;
const ziqlToken = @import("tokenizers/ziql.zig").Token;
const ziqlParser = @import("ziqlParser.zig").Parser;
const utils = @import("utils.zig");

const stdout = std.io.getStdOut().writer();

// TODO: Use some global var like that
const version = "0.0.9";

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
    expect_db_command,
    expect_path_to_new_db,
    expect_path_to_db,
    quit,
    end,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer switch (gpa.deinit()) {
        .ok => {},
        .leak => std.log.debug("We fucked it up bro...\n", .{}),
    };

    const path_env_variable = utils.getEnvVariables(allocator, "ZIPPONDB_PATH");
    defer if (path_env_variable) |path| allocator.free(path);
    var file_engine: FileEngine = undefined;
    defer file_engine.deinit();

    if (path_env_variable) |path| {
        std.debug.print("Environment variable found: {s}\n", .{path});
        file_engine = FileEngine.init(allocator, path_env_variable.?);
    } else {
        file_engine = FileEngine.init(allocator, "");
        std.debug.print("No ZIPONDB_PATH envirionment variable found, please use the command:\n db use path/to/db \nor\n db new /path/to/dir\n", .{});
    }

    const line_buf = try allocator.alloc(u8, 1024 * 50);
    defer allocator.free(line_buf);

    var state: State = .expect_main_command;

    while (true) {
        std.debug.print("> ", .{});
        const line = try std.io.getStdIn().reader().readUntilDelimiterOrEof(line_buf, '\n');

        if (line) |line_str| {
            const null_term_line_str = try allocator.dupeZ(u8, line_str[0..line_str.len]);
            defer allocator.free(null_term_line_str);

            var cliToker = cliTokenizer.init(null_term_line_str);
            var token = cliToker.next();
            state = .expect_main_command;

            while ((state != .end) and (state != .quit)) : (token = cliToker.next()) {
                switch (state) {
                    .expect_main_command => switch (token.tag) {
                        .keyword_run => {
                            if (!file_engine.usable) {
                                send("Error: No database selected. Please use db new or db use.", .{});
                                state = .end;
                                continue;
                            }
                            state = .expect_query;
                        },
                        .keyword_db => state = .expect_db_command,
                        .keyword_schema => {
                            if (!file_engine.usable) {
                                send("Error: No database selected. Please use db new or db use.", .{});
                                state = .end;
                                continue;
                            }
                            state = .expect_schema_command;
                        },
                        .keyword_help => {
                            send("{s}", .{
                                \\Welcome to ZipponDB v0.1!
                                \\
                                \\Available commands:
                                \\run       To run a query.
                                \\db        Create or chose a database.
                                \\schema    Initialize the database schema.
                                \\quit      Stop the CLI with memory safety.
                                \\
                                \\ For more informations: https://github.com/MrBounty/ZipponDB
                                \\
                            });
                            state = .end;
                        },
                        .keyword_quit => state = .quit,
                        .eof => state = .end,
                        else => {
                            send("Command need to start with a keyword, including: run, db, schema, help and quit", .{});
                            state = .end;
                        },
                    },

                    .expect_db_command => switch (token.tag) {
                        .keyword_new => state = .expect_path_to_new_db,
                        .keyword_use => state = .expect_path_to_db,
                        .keyword_metrics => {
                            if (!file_engine.usable) {
                                send("Error: No database selected. Please use db new or db use.", .{});
                                state = .end;
                                continue;
                            }

                            var buffer = std.ArrayList(u8).init(allocator);
                            defer buffer.deinit();

                            try file_engine.writeDbMetrics(&buffer);
                            send("{s}", .{buffer.items});
                            state = .end;
                        },
                        .keyword_help => {
                            send("{s}", .{
                                \\Available commands:
                                \\new       Create a new database using a path to a sub folder.
                                \\use       Select another ZipponDB folder to use as database.
                                \\metrics   Print some metrics of the current database.
                                \\
                                \\ For more informations: https://github.com/MrBounty/ZipponDB
                                \\
                            });
                            state = .end;
                        },
                        else => {
                            send("Error: db commands available: new, metrics, swap & help", .{});
                            state = .end;
                        },
                    },

                    .expect_path_to_db => switch (token.tag) {
                        .identifier => {
                            file_engine.deinit();
                            file_engine = FileEngine.init(allocator, cliToker.getTokenSlice(token));
                            send("Successfully started using the database!", .{});
                            state = .end;
                        },
                        else => {
                            send("Error Expect a path to a ZipponDB folder.", .{});
                            state = .end;
                        },
                    },

                    .expect_path_to_new_db => switch (token.tag) {
                        .identifier => {
                            checkAndCreateDirectories(cliToker.getTokenSlice(token), allocator) catch |err| {
                                send("Error: Coulnt create database directories: {any}", .{err});
                                state = .end;
                                continue;
                            };
                            file_engine.deinit();
                            file_engine = FileEngine.init(allocator, cliToker.getTokenSlice(token));
                            send("Successfully initialized the database!", .{});
                            state = .end;
                        },
                        else => {
                            send("Error Expect a path to a folder.", .{});
                            state = .end;
                        },
                    },

                    .expect_query => switch (token.tag) {
                        .string_literal => {
                            const null_term_query_str = try allocator.dupeZ(u8, line_str[token.loc.start + 1 .. token.loc.end - 1]);
                            defer allocator.free(null_term_query_str);
                            runQuery(null_term_query_str, &file_engine);
                            state = .end;
                        },
                        .keyword_help => {
                            send("The run command take a ZiQL query between \" and run it. eg: run \"GRAB User\"", .{});
                            state = .end;
                        },
                        else => {
                            send("Error: After command run, need a query, eg: \"GRAB User\"", .{});
                            state = .end;
                        },
                    },

                    .expect_schema_command => switch (token.tag) {
                        .keyword_describe => {
                            if (std.mem.eql(u8, file_engine.path_to_ZipponDB_dir, "")) send("Error: No database selected. Please use db bew or db use.", .{});

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
                                \\Available commands:
                                \\describe  Print the schema use by the currently selected database.
                                \\init      Take the path to a schema file and initialize the database.
                                \\
                                \\ For more informations: https://github.com/MrBounty/ZipponDB
                                \\
                            });
                            state = .end;
                        },
                        else => {
                            send("Error: schema commands available: describe, init & help", .{});
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
                            send("Successfully initialized the database schema!", .{});
                            state = .end;
                        },
                        else => {
                            send("Error: Expect path to schema file.", .{});
                            state = .end;
                        },
                    },

                    .quit, .end => break,
                }
            }
            if (state == .quit) break;
        }
    }
}

pub fn runQuery(null_term_query_str: [:0]const u8, file_engine: *FileEngine) void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var toker = ziqlTokenizer.init(null_term_query_str);

    var parser = ziqlParser.init(allocator, &toker, file_engine);
    defer {
        parser.deinit();
        switch (gpa.deinit()) {
            .ok => {},
            .leak => std.log.debug("We fucked it up bro...\n", .{}),
        }
    }

    parser.parse() catch |err| switch (err) {
        error.SynthaxError => {},
        else => {},
    };
}

// TODO: Put that in the FileEngine
fn checkAndCreateDirectories(sub_path: []const u8, allocator: Allocator) !void {
    var path_buff = try std.fmt.allocPrint(allocator, "{s}/ZipponDB", .{sub_path});
    defer allocator.free(path_buff);

    const cwd = std.fs.cwd();

    cwd.makeDir(path_buff) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    allocator.free(path_buff);
    path_buff = try std.fmt.allocPrint(allocator, "{s}/ZipponDB/DATA", .{sub_path});

    cwd.makeDir(path_buff) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    allocator.free(path_buff);
    path_buff = try std.fmt.allocPrint(allocator, "{s}/ZipponDB/BACKUP", .{sub_path});

    cwd.makeDir(path_buff) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    allocator.free(path_buff);
    path_buff = try std.fmt.allocPrint(allocator, "{s}/ZipponDB/LOG", .{sub_path});

    cwd.makeDir(path_buff) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}
