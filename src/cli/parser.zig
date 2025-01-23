const std = @import("std");
const cliTokenizer = @import("tokenizer.zig").Tokenizer;
const cliToken = @import("tokenizer.zig").Token;
const send = @import("../utils.zig").send;
const config = @import("config");
const log = std.log.scoped(.cli);

const State = enum {
    expect_main_command,
    expect_query,
    expect_schema_command,
    expect_path_to_schema,
    expect_db_command,
    expect_path_to_db,
    expect_file_format,
    expect_path_to_dump,
    quit,
    end,
};

const Self = @import("core.zig");

pub fn parse(self: *Self, null_term_line_str: [:0]const u8) !bool {
    var toker = cliTokenizer.init(null_term_line_str);
    var token = toker.next();
    var state = State.expect_main_command;

    var arena = std.heap.ArenaAllocator.init(self.allocator);
    var allocator = arena.allocator();
    defer arena.deinit();

    var last_token: cliToken = undefined;

    while ((state != .end) and (state != .quit)) : ({
        last_token = token;
        token = toker.next();
    }) switch (state) {
        .expect_main_command => switch (token.tag) {
            .keyword_run => {
                if (self.state == .MissingFileEngine) {
                    send("{s}", .{config.HELP_MESSAGE.no_engine});
                    state = .end;
                    continue;
                }
                if (self.state == .MissingSchemaEngine) {
                    send(config.HELP_MESSAGE.no_schema, .{self.file_engine.path_to_ZipponDB_dir});
                    state = .end;
                    continue;
                }
                state = .expect_query;
            },
            .keyword_db => state = .expect_db_command,
            .keyword_schema => {
                if (self.state == .MissingFileEngine) {
                    send("{s}", .{config.HELP_MESSAGE.no_engine});
                    state = .end;
                    continue;
                }
                state = .expect_schema_command;
            },
            .keyword_help => {
                send("{s}", .{config.HELP_MESSAGE.main});
                state = .end;
            },
            .keyword_quit => state = .quit,
            .keyword_dump => {
                if (self.state == .MissingFileEngine) {
                    send("{s}", .{config.HELP_MESSAGE.no_engine});
                    state = .end;
                    continue;
                }
                if (self.state == .MissingSchemaEngine) {
                    send(config.HELP_MESSAGE.no_schema, .{self.file_engine.path_to_ZipponDB_dir});
                    state = .end;
                    continue;
                }
                state = .expect_file_format;
            },
            .eof => state = .end,
            else => {
                send("Command need to start with a keyword, including: run, db, schema, help and quit", .{});
                state = .end;
            },
        },

        .expect_file_format => switch (token.tag) {
            .keyword_csv => state = .expect_path_to_dump,
            .keyword_json => state = .expect_path_to_dump,
            .keyword_zid => state = .expect_path_to_dump,
            .keyword_help => {
                send("{s}", .{config.HELP_MESSAGE.dump});
                state = .end;
            },
            else => {
                send("Error: format available: csv, json, zid", .{});
                state = .end;
            },
        },

        .expect_db_command => switch (token.tag) {
            .keyword_use => state = .expect_path_to_db,
            .keyword_metrics => {
                if (self.state == .MissingFileEngine) {
                    send("{s}", .{config.HELP_MESSAGE.no_engine});
                    state = .end;
                    continue;
                }
                if (self.state == .MissingSchemaEngine) {
                    send(config.HELP_MESSAGE.no_schema, .{self.file_engine.path_to_ZipponDB_dir});
                    state = .end;
                    continue;
                }

                var buffer = std.ArrayList(u8).init(allocator);
                defer buffer.deinit();

                try self.file_engine.writeDbMetrics(&buffer);
                send("{s}", .{buffer.items});
                state = .end;
            },
            .keyword_state => {
                send("{any}", .{self.state});
                state = .end;
            },
            .keyword_help => {
                send("{s}", .{config.HELP_MESSAGE.db});
                state = .end;
            },
            else => {
                send("Error: db commands available: use, metrics & help", .{});
                state = .end;
            },
        },

        .expect_path_to_db => switch (token.tag) {
            .identifier => {
                self.deinit();
                self.* = Self.init(self.allocator, toker.getTokenSlice(token), null);
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
                self.runQuery(null_term_query_str); // This should most probably return something and I should send from here, not from the parser
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
                if (self.state == .MissingFileEngine) {
                    send("{s}", .{config.HELP_MESSAGE.no_engine});
                    state = .end;
                    continue;
                }
                if (self.state == .MissingSchemaEngine) {
                    send(config.HELP_MESSAGE.no_schema, .{self.file_engine.path_to_ZipponDB_dir});
                    state = .end;
                    continue;
                }
                send("Schema:\n {s}", .{self.schema_engine.null_terminated});
                state = .end;
            },
            .keyword_use => {
                if (self.state == .MissingFileEngine) send("Error: No database selected. Please use 'db use'.", .{});
                state = .expect_path_to_schema;
            },
            .keyword_help => {
                send("{s}", .{config.HELP_MESSAGE.schema});
                state = .end;
            },
            else => {
                send("{s}", .{config.HELP_MESSAGE.schema});
                state = .end;
            },
        },

        .expect_path_to_schema => switch (token.tag) {
            .identifier => {
                const main_path = try allocator.dupe(u8, self.file_engine.path_to_ZipponDB_dir);
                self.deinit();
                self.* = Self.init(self.allocator, main_path, toker.getTokenSlice(token));
                try self.file_engine.writeSchemaFile(self.schema_engine.null_terminated);
                state = .end;
            },
            else => {
                send("Error: Expect path to schema file.", .{});
                state = .end;
            },
        },

        .expect_path_to_dump => switch (token.tag) {
            .identifier => {
                try self.file_engine.dumpDb(allocator, toker.getTokenSlice(token), switch (last_token.tag) {
                    .keyword_csv => .csv,
                    .keyword_zid => .zid,
                    .keyword_json => .json,
                    else => unreachable,
                });
                state = .end;
            },
            else => {
                send("Error: Expect path to dump dir.", .{});
                state = .end;
            },
        },

        .quit, .end => unreachable,
    };

    if (state == .quit) {
        arena.deinit();
        log.info("Bye bye\n", .{});
        return true;
    }

    return false;
}
