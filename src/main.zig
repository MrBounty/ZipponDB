const std = @import("std");
const utils = @import("stuffs/utils.zig");
const send = utils.send;
const Allocator = std.mem.Allocator;
const Pool = std.Thread.Pool;

const FileEngine = @import("fileEngine.zig").FileEngine;
const SchemaEngine = @import("schemaEngine.zig").SchemaEngine;
const ThreadEngine = @import("threadEngine.zig").ThreadEngine;

const cliTokenizer = @import("tokenizers/cli.zig").Tokenizer;
const cliToken = @import("tokenizers/cli.zig").Token;

const ziqlTokenizer = @import("tokenizers/ziql.zig").Tokenizer;
const ziqlToken = @import("tokenizers/ziql.zig").Token;
const ziqlParser = @import("ziqlParser.zig").Parser;

const ZipponError = @import("stuffs/errors.zig").ZipponError;

const config = @import("config.zig");
const BUFFER_SIZE = config.BUFFER_SIZE;
const CPU_CORE = config.CPU_CORE;
const HELP_MESSAGE = config.HELP_MESSAGE;

const State = enum {
    expect_main_command,
    expect_query,
    expect_schema_command,
    expect_path_to_schema,
    expect_db_command,
    expect_path_to_db,
    quit,
    end,
};

const log_allocator = std.heap.page_allocator;
var log_buff: [1024]u8 = undefined;
var log_path: []const u8 = undefined;
var path_buffer: [1024]u8 = undefined;
var line_buffer: [BUFFER_SIZE]u8 = undefined;
var in_buffer: [BUFFER_SIZE]u8 = undefined;
var out_buffer: [BUFFER_SIZE]u8 = undefined;

const log = std.log.scoped(.cli);
pub const std_options = .{
    .logFn = myLog,
};

const DBEngineState = enum { MissingFileEngine, MissingSchemaEngine, Ok, Init };

pub const DBEngine = struct {
    state: DBEngineState = .Init,
    file_engine: FileEngine = undefined,
    schema_engine: SchemaEngine = undefined,
    thread_engine: ThreadEngine = undefined,

    pub fn init(potential_main_path: ?[]const u8, potential_schema_path: ?[]const u8) DBEngine {
        var self = DBEngine{};

        self.thread_engine = ThreadEngine.init();

        const potential_main_path_or_environment_variable = potential_main_path orelse utils.getEnvVariable("ZIPPONDB_PATH");
        if (potential_main_path_or_environment_variable) |main_path| {
            log_path = std.fmt.bufPrint(&log_buff, "{s}/LOG/log", .{main_path}) catch "";
            log.info("Found ZIPPONDB_PATH: {s}.", .{main_path});
            self.file_engine = FileEngine.init(main_path, self.thread_engine.thread_pool) catch {
                log.err("Error when init FileEngine", .{});
                self.state = .MissingFileEngine;
                return self;
            };
            self.file_engine.createMainDirectories() catch {
                log.err("Error when creating main directories", .{});
                self.state = .MissingFileEngine;
                return self;
            };

            self.state = .MissingSchemaEngine;
        } else {
            log.info("No ZIPPONDB_PATH found.", .{});
            self.state = .MissingFileEngine;
            return self;
        }

        if (self.file_engine.isSchemaFileInDir() and potential_schema_path == null) {
            const schema_path = std.fmt.bufPrint(&path_buffer, "{s}/schema", .{self.file_engine.path_to_ZipponDB_dir}) catch {
                self.state = .MissingSchemaEngine;
                return self;
            };

            log.info("Schema founded in the database directory.", .{});
            self.schema_engine = SchemaEngine.init(schema_path, &self.file_engine) catch |err| {
                log.err("Error when init SchemaEngine: {any}", .{err});
                self.state = .MissingSchemaEngine;
                return self;
            };
            self.file_engine.createStructDirectories(self.schema_engine.struct_array) catch |err| {
                log.err("Error when creating struct directories: {any}", .{err});
                self.schema_engine.deinit();
                self.state = .MissingSchemaEngine;
                return self;
            };

            log.debug("SchemaEngine created in DBEngine with {d} struct", .{self.schema_engine.struct_array.len});

            self.file_engine.schema_engine = self.schema_engine;
            self.state = .Ok;
            return self;
        }

        log.info("Database don't have any schema yet, trying to add one.", .{});
        const potential_schema_path_or_environment_variable = potential_schema_path orelse utils.getEnvVariable("ZIPPONDB_SCHEMA");
        if (potential_schema_path_or_environment_variable) |schema_path| {
            log.info("Found schema path {s}.", .{schema_path});
            self.schema_engine = SchemaEngine.init(schema_path, &self.file_engine) catch |err| {
                log.err("Error when init SchemaEngine: {any}", .{err});
                self.state = .MissingSchemaEngine;
                return self;
            };
            self.file_engine.createStructDirectories(self.schema_engine.struct_array) catch |err| {
                log.err("Error when creating struct directories: {any}", .{err});
                self.schema_engine.deinit();
                self.state = .MissingSchemaEngine;
                return self;
            };
            self.file_engine.schema_engine = self.schema_engine;
            self.state = .Ok;
        } else {
            log.info(HELP_MESSAGE.no_schema, .{self.file_engine.path_to_ZipponDB_dir});
        }

        return self;
    }

    pub fn deinit(self: *DBEngine) void {
        if (self.state == .Ok) self.schema_engine.deinit();
    }

    pub fn runQuery(self: *DBEngine, null_term_query_str: [:0]const u8) void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){}; // Maybe use an arena here
        const allocator = gpa.allocator();

        var toker = ziqlTokenizer.init(null_term_query_str);

        var parser = ziqlParser.init(
            allocator,
            &toker,
            &self.file_engine,
            &self.schema_engine,
        );

        parser.parse() catch |err| {
            log.err("Error parsing: {any}", .{err});
        };

        switch (gpa.deinit()) {
            .ok => {},
            .leak => std.log.debug("We fucked it up bro...\n", .{}),
        }
    }
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

    const now = @import("dtype").DateTime.now();
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
    var db_engine = DBEngine.init(null, null);
    defer db_engine.deinit();

    var fa = std.heap.FixedBufferAllocator.init(&out_buffer);
    const allocator = fa.allocator();

    while (true) {
        fa.reset();
        db_engine.thread_engine.reset();
        std.debug.print("> ", .{}); // TODO: Find something better than just std.debug.print
        const line = std.io.getStdIn().reader().readUntilDelimiterOrEof(&in_buffer, '\n') catch {
            log.debug("Command too long for buffer", .{});
            continue;
        };

        if (line) |line_str| {
            const start_time = std.time.milliTimestamp();
            log.debug("Query received: {s}", .{line_str});

            const null_term_line_str = try std.fmt.bufPrintZ(&line_buffer, "{s}", .{line_str});

            var toker = cliTokenizer.init(null_term_line_str);
            var token = toker.next();
            var state = State.expect_main_command;

            while ((state != .end) and (state != .quit)) : (token = toker.next()) switch (state) {
                .expect_main_command => switch (token.tag) {
                    .keyword_run => {
                        if (db_engine.state == .MissingFileEngine) {
                            send("{s}", .{HELP_MESSAGE.no_engine});
                            state = .end;
                            continue;
                        }
                        if (db_engine.state == .MissingSchemaEngine) {
                            send(HELP_MESSAGE.no_schema, .{db_engine.file_engine.path_to_ZipponDB_dir});
                            state = .end;
                            continue;
                        }
                        state = .expect_query;
                    },
                    .keyword_db => state = .expect_db_command,
                    .keyword_schema => {
                        if (db_engine.state == .MissingFileEngine) {
                            send("{s}", .{HELP_MESSAGE.no_engine});
                            state = .end;
                            continue;
                        }
                        state = .expect_schema_command;
                    },
                    .keyword_help => {
                        send("{s}", .{HELP_MESSAGE.main});
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
                    .keyword_new, .keyword_use => state = .expect_path_to_db, //TODO: When new, create the dir. If use, dont create the dir
                    .keyword_metrics => {
                        if (db_engine.state == .MissingFileEngine) {
                            send("{s}", .{HELP_MESSAGE.no_engine});
                            state = .end;
                            continue;
                        }
                        if (db_engine.state == .MissingSchemaEngine) {
                            send(HELP_MESSAGE.no_schema, .{db_engine.file_engine.path_to_ZipponDB_dir});
                            state = .end;
                            continue;
                        }

                        var buffer = std.ArrayList(u8).init(allocator);
                        defer buffer.deinit();

                        try db_engine.file_engine.writeDbMetrics(&buffer);
                        send("{s}", .{buffer.items});
                        state = .end;
                    },
                    .keyword_help => {
                        send("{s}", .{HELP_MESSAGE.db});
                        state = .end;
                    },
                    else => {
                        send("Error: db commands available: new, metrics, swap & help", .{});
                        state = .end;
                    },
                },

                .expect_path_to_db => switch (token.tag) {
                    .identifier => {
                        db_engine.deinit();
                        db_engine = DBEngine.init(toker.getTokenSlice(token), null);
                        state = .end;
                    },
                    else => {
                        send("Error Expect a path to a ZipponDB folder.", .{});
                        state = .end;
                    },
                },

                .expect_query => switch (token.tag) {
                    .string_literal => {
                        const null_term_query_str = try allocator.dupeZ(u8, toker.buffer[token.loc.start + 1 .. token.loc.end - 1]);
                        defer allocator.free(null_term_query_str);
                        db_engine.runQuery(null_term_query_str); // TODO: THis should return something and I should send from here, not from the parser
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
                        if (db_engine.state == .MissingFileEngine) send("Error: No database selected. Please use 'db new' or 'db use'.", .{});
                        if (db_engine.state == .MissingSchemaEngine) send("Error: No schema in database. Please use 'schema init'.", .{});
                        send("Schema:\n {s}", .{db_engine.schema_engine.null_terminated});
                        state = .end;
                    },
                    .keyword_init => {
                        if (db_engine.state == .MissingFileEngine) send("Error: No database selected. Please use 'db new' or 'db use'.", .{});
                        state = .expect_path_to_schema;
                    },
                    .keyword_help => {
                        send("{s}", .{HELP_MESSAGE.schema});
                        state = .end;
                    },
                    else => {
                        send("{s}", .{HELP_MESSAGE.schema});
                        state = .end;
                    },
                },

                .expect_path_to_schema => switch (token.tag) {
                    .identifier => {
                        const main_path = try allocator.dupe(u8, db_engine.file_engine.path_to_ZipponDB_dir);
                        db_engine.deinit();
                        db_engine = DBEngine.init(main_path, toker.getTokenSlice(token));
                        try db_engine.file_engine.writeSchemaFile(db_engine.schema_engine.null_terminated);
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
            const end_time = std.time.milliTimestamp();
            std.debug.print("Finished in: {d}ms\n", .{end_time - start_time});
        }
    }
}
