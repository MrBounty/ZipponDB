const std = @import("std");
const Allocator = std.mem.Allocator;

// TODO: Clean that
const DateTime = @import("types/date.zig").DateTime;
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

const log_allocator = std.heap.page_allocator;
var log_buff: [1024]u8 = undefined;
var log_path: []const u8 = undefined;

const log = std.log.scoped(.cli);
pub const std_options = .{
    .logFn = myLog,
};

pub fn myLog(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime message_level.asText();
    const prefix = if (scope == .default) " - " else "(" ++ @tagName(scope) ++ ") - ";

    const potential_file: ?std.fs.File = std.fs.cwd().openFile(log_path, .{ .mode = .write_only }) catch null;

    const now = DateTime.now();
    var date_format_buffer = std.ArrayList(u8).init(log_allocator);
    defer date_format_buffer.deinit();
    now.format("YYYY/MM/DD-HH:mm:ss.SSSS", date_format_buffer.writer()) catch return;

    if (potential_file) |file| {
        file.seekFromEnd(0) catch return;
        const writer = file.writer();

        writer.print("{s}{s}Time: {s} - ", .{ level_txt, prefix, date_format_buffer.items }) catch return;
        writer.print(format, args) catch return;
        writer.writeByte('\n') catch return;
        file.close();
    } else {
        const writer = std.io.getStdErr().writer();

        writer.print("{s}{s}Time: {s} - ", .{ level_txt, prefix, date_format_buffer.items }) catch return;
        writer.print(format, args) catch return;
        writer.writeByte('\n') catch return;
    }
}

// TODO: If an argument is given when starting the binary, it is the db path
pub fn main() !void {
    var state: State = .expect_main_command;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer switch (gpa.deinit()) {
        .ok => {},
        .leak => std.log.debug("We fucked it up bro...\n", .{}),
    };

    var file_engine = try initFileEngine.init(allocator, null);
    defer file_engine.deinit();

    const line_buf = try allocator.alloc(u8, BUFFER_SIZE);
    defer allocator.free(line_buf);

    while (true) {
        std.debug.print("> ", .{});
        const line = try std.io.getStdIn().reader().readUntilDelimiterOrEof(line_buf, '\n');

        if (line) |line_str| {
            log.debug("Query received: {s}", .{line_str});

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
                        file_engine = try initFileEngine.init(allocator, try allocator.dupe(u8, toker.getTokenSlice(token)));
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

            if (state == .quit) {
                log.info("Bye bye\n", .{});
                break;
            }
        }
    }
}

pub fn runQuery(null_term_query_str: [:0]const u8, file_engine: *FileEngine) void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var toker = ziqlTokenizer.init(null_term_query_str);

    var parser = ziqlParser.init(allocator, &toker, file_engine);

    parser.parse() catch |err| {
        log.err("Error parsing: {any}", .{err});
    };

    switch (gpa.deinit()) {
        .ok => {},
        .leak => std.log.debug("We fucked it up bro...\n", .{}),
    }
}

/// Simple struct to manage the init of the FileEngine, mostly managing if env path is here and init the directories, ect
const initFileEngine = struct {
    fn init(allocator: std.mem.Allocator, potential_path: ?[]const u8) !FileEngine {
        if (potential_path) |p| {
            log_path = try std.fmt.bufPrint(&log_buff, "{s}/LOG/log", .{p});
            log.info("Start using database path: {s}.", .{p});
            return try initWithPath(allocator, p);
        }

        const path = utils.getEnvVariable(allocator, "ZIPPONDB_PATH");
        defer if (path) |p| allocator.free(p);

        if (path) |p| {
            log_path = try std.fmt.bufPrint(&log_buff, "{s}/LOG/log", .{p});
            log.info("Found environment variable ZIPPONDB_PATH: {s}.", .{p});
            return try initWithPath(allocator, p);
        } else {
            log.info("No environment variable ZIPPONDB_PATH found.", .{});
            return FileEngine.init(allocator, "");
        }
    }

    fn initWithPath(allocator: std.mem.Allocator, path: []const u8) !FileEngine {
        try ensureDirectoryExists(path);
        var file_engine = FileEngine.init(allocator, path);
        try file_engine.checkAndCreateDirectories();

        if (!file_engine.isSchemaFileInDir()) {
            try initSchema(allocator, &file_engine);
        } else {
            std.debug.print("Database has a schema.\n", .{});
        }

        return file_engine;
    }

    fn ensureDirectoryExists(path: []const u8) !void {
        _ = std.fs.cwd().openDir(path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                log.info("{s} directory not found, creating it\n", .{path});
                try std.fs.cwd().makeDir(path);
                return;
            } else {
                return err;
            }
        };
    }

    fn initSchema(allocator: std.mem.Allocator, file_engine: *FileEngine) !void {
        log.debug("Database doesn't have any schema. Checking if ZIPPONDB_SCHEMA env variable exists.", .{});
        const schema = utils.getEnvVariable(allocator, "ZIPPONDB_SCHEMA");
        defer if (schema) |s| allocator.free(s);

        if (schema) |s| {
            log.debug("Found environment variable ZIPPONDB_SCHEMA: {s}.", .{s});
            file_engine.initDataFolder(s) catch {
                std.debug.print("Couldn't use {s} as schema.\n", .{s});
            };
        } else {
            log.debug("No environment variable ZIPPONDB_SCHEMA found.", .{});
        }
    }
};
