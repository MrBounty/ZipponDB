const std = @import("std");
const Allocator = std.mem.Allocator;
const FileEngine = @import("fileEngine.zig").FileEngine;
const cliTokenizer = @import("tokenizers/cli.zig").Tokenizer;
const cliToken = @import("tokenizers/cli.zig").Token;
const ziqlTokenizer = @import("tokenizers/ziql.zig").Tokenizer;
const ziqlToken = @import("tokenizers/ziql.zig").Token;
const ziqlParser = @import("ziqlParser.zig").Parser;
const utils = @import("stuffs/utils.zig");
const send = @import("stuffs/utils.zig").send;

const BUFFER_SIZE = @import("config.zig").BUFFER_SIZE;

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

// TODO: If an argument is given when starting the binary, it is the db path
pub fn main() !void {
    var state: State = .expect_main_command;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer switch (gpa.deinit()) {
        .ok => {},
        .leak => std.log.debug("We fucked it up bro...\n", .{}),
    };

    const path_env_variable = utils.getEnvVariables(allocator, "ZIPPONDB_PATH");
    var file_engine: FileEngine = undefined;
    defer file_engine.deinit();

    if (path_env_variable) |path| {
        std.debug.print("Found envirionment variable ZIPPONDB_PATH: {s}.\n", .{path});
        var to_init = true;
        _ = std.fs.cwd().openDir(path, .{}) catch {
            std.debug.print("{s} directory not found, creating it\n", .{path});
            std.fs.cwd().makeDir(path) catch {
                std.debug.print("{s} couldnt be make. Please use 'db new' or 'db use'.\n", .{path});
                file_engine = FileEngine.init(allocator, "");
                to_init = false;
            };
        };
        if (to_init) {
            file_engine = FileEngine.init(allocator, path);
            try file_engine.checkAndCreateDirectories();
            //file_engine.createLog("main");
            file_engine.log("main", .Info, "Found envirionment variable ZIPPONDB_PATH: {s}", .{path});
        }

        // Check if the db have a schema
        if (!file_engine.isSchemaFileInDir()) {
            std.debug.print("Database don't have any schema. Checking if ZIPPONDB_SCHEMA env variable exist.\n", .{});
            const schema_env_variable = utils.getEnvVariables(allocator, "ZIPPONDB_SCHEMA");
            if (schema_env_variable) |schema| {
                std.debug.print("Found envirionment variable ZIPPONDB_SCHEMA {s}.\n", .{schema});
                file_engine.initDataFolder(schema) catch {
                    std.debug.print("Couldn't use {s} as schema.\n", .{schema});
                };
            } else {
                std.debug.print("No envirionment variable ZIPPONDB_SCHEMA found.\n", .{});
            }
        } else {
            std.debug.print("Database have a schema.\n", .{});
        }
    } else {
        std.debug.print("No envirionment variable ZIPPONDB_PATH found.\n", .{});
        file_engine = FileEngine.init(allocator, "");
    }

    const line_buf = try allocator.alloc(u8, BUFFER_SIZE);
    defer allocator.free(line_buf);

    while (true) {
        std.debug.print("> ", .{});
        const line = try std.io.getStdIn().reader().readUntilDelimiterOrEof(line_buf, '\n');

        if (line) |line_str| {
            file_engine.log("main", .Info, "Query received: {s}", .{line_str});

            const null_term_line_str = try allocator.dupeZ(u8, line_str[0..line_str.len]);
            defer allocator.free(null_term_line_str);

            var toker = cliTokenizer.init(null_term_line_str);
            var token = toker.next();
            state = .expect_main_command;

            while ((state != .end) and (state != .quit)) : (token = toker.next()) switch (state) {
                .expect_main_command => switch (token.tag) {
                    .keyword_run => {
                        if (!file_engine.usable()) {
                            send("Error: No database selected. Please use db new or db use.", .{});
                            state = .end;
                            continue;
                        }
                        state = .expect_query;
                    },
                    .keyword_db => state = .expect_db_command,
                    .keyword_schema => {
                        if (!file_engine.usable()) {
                            send("Error: No database selected. Please use db new or db use.", .{});
                            state = .end;
                            continue;
                        }
                        state = .expect_schema_command;
                    },
                    .keyword_help => {
                        send("{s}", .{
                            \\Welcome to ZipponDB v0.1.1!
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
                        if (!file_engine.usable()) {
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
                        file_engine = FileEngine.init(allocator, try allocator.dupe(u8, toker.getTokenSlice(token)));
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
                        file_engine.deinit();
                        file_engine = FileEngine.init(allocator, try allocator.dupe(u8, toker.getTokenSlice(token)));
                        file_engine.checkAndCreateDirectories() catch |err| {
                            send("Error: Coulnt create database directories: {any}", .{err});
                            state = .end;
                            continue;
                        };
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
                        const null_term_query_str = try allocator.dupeZ(u8, toker.buffer[token.loc.start + 1 .. token.loc.end - 1]);
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
                        file_engine.initDataFolder(toker.getTokenSlice(token)) catch |err| switch (err) {
                            error.SchemaFileNotFound => {
                                send("Coulnt find the schema file at {s}", .{toker.getTokenSlice(token)});
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

                .quit, .end => unreachable,
            };

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

    parser.parse() catch |err| {
        file_engine.log("main", .Error, "Error parsing: {any}", .{err});
    };
}

// TODO: Put that in the FileEngine
