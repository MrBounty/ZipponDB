// From https://github.com/ziglang/zig/blob/master/lib/std/zig/tokenizer.zig
const std = @import("std");
const Loc = @import("shared/loc.zig").Loc;

pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const keywords = std.StaticStringMap(Tag).initComptime(.{
        .{ "run", .keyword_run },
        .{ "help", .keyword_help },
        .{ "describe", .keyword_describe },
        .{ "init", .keyword_init },
        .{ "schema", .keyword_schema },
        .{ "quit", .keyword_quit },
        .{ "db", .keyword_db },
        .{ "new", .keyword_new },
        .{ "metrics", .keyword_metrics },
        .{ "use", .keyword_use },
        .{ "state", .keyword_state },
        .{ "dump", .keyword_dump },
        .{ "csv", .keyword_csv },
        .{ "json", .keyword_json },
        .{ "zid", .keyword_zid },
    });

    pub fn getKeyword(bytes: []const u8) ?Tag {
        return keywords.get(bytes);
    }

    pub const Tag = enum {
        eof,
        invalid,

        keyword_run,
        keyword_help,
        keyword_describe,
        keyword_schema,
        keyword_init,
        keyword_quit,
        keyword_db,
        keyword_new,
        keyword_metrics,
        keyword_use,
        keyword_state,
        keyword_dump,
        keyword_csv,
        keyword_json,
        keyword_zid,

        string_literal,
        identifier,
    };
};

pub const Tokenizer = struct {
    buffer: [:0]const u8,
    index: usize,

    pub fn init(buffer: [:0]const u8) Tokenizer {
        // Skip the UTF-8 BOM if present.
        return .{
            .buffer = buffer,
            .index = if (std.mem.startsWith(u8, buffer, "\xEF\xBB\xBF")) 3 else 0,
        };
    }

    const State = enum {
        start,
        invalid,
        identifier,
        string_literal,
        string_literal_backslash,
    };

    pub fn getTokenSlice(self: *Tokenizer, token: Token) []const u8 {
        return self.buffer[token.loc.start..token.loc.end];
    }

    pub fn next(self: *Tokenizer) Token {
        var state: State = .start;
        var result: Token = .{
            .tag = undefined,
            .loc = .{
                .start = self.index,
                .end = undefined,
            },
        };
        while (true) : (self.index += 1) {
            const c = self.buffer[self.index];
            switch (state) {
                .start => switch (c) {
                    0 => {
                        if (self.index == self.buffer.len) return .{
                            .tag = .eof,
                            .loc = .{
                                .start = self.index,
                                .end = self.index,
                            },
                        };
                        state = .invalid;
                    },
                    ' ', '\n', '\t', '\r' => {
                        result.loc.start = self.index + 1;
                    },
                    'a'...'z', 'A'...'Z', '_' => {
                        state = .identifier;
                        result.tag = .identifier;
                    },
                    '"' => {
                        state = .string_literal;
                        result.tag = .string_literal;
                    },
                    else => {
                        state = .invalid;
                    },
                },

                .invalid => {
                    result.tag = .invalid;
                    break;
                },

                .identifier => switch (c) {
                    'a'...'z', 'A'...'Z', '_', '0'...'9', '.', '/' => continue,
                    else => {
                        if (Token.getKeyword(self.buffer[result.loc.start..self.index])) |tag| {
                            result.tag = tag;
                        }
                        break;
                    },
                },

                .string_literal => switch (c) {
                    0 => {
                        if (self.index != self.buffer.len) {
                            state = .invalid;
                            continue;
                        }
                        result.tag = .invalid;
                        break;
                    },
                    '\n' => {
                        result.tag = .invalid;
                        break;
                    },
                    '\\' => {
                        state = .string_literal_backslash;
                    },
                    '"' => {
                        self.index += 1;
                        break;
                    },
                    0x01...0x09, 0x0b...0x1f, 0x7f => {
                        state = .invalid;
                    },
                    else => continue,
                },

                .string_literal_backslash => switch (c) {
                    0, '\n' => {
                        result.tag = .invalid;
                        break;
                    },
                    else => {
                        state = .string_literal;
                    },
                },
            }
        }

        result.loc.end = self.index;
        return result;
    }
};

test "Basics" {
    try testTokenize("help", &.{.keyword_help});
    try testTokenize("run \"Hello world\"", &.{ .keyword_run, .string_literal });
}

fn testTokenize(source: [:0]const u8, expected_token_tags: []const Token.Tag) !void {
    var tokenizer = Tokenizer.init(source);
    for (expected_token_tags) |expected_token_tag| {
        const token = tokenizer.next();
        try std.testing.expectEqual(expected_token_tag, token.tag);
    }
    // Last token should always be eof, even when the last token was invalid,
    // in which case the tokenizer is in an invalid state, which can only be
    // recovered by opinionated means outside the scope of this implementation.
    const last_token = tokenizer.next();
    try std.testing.expectEqual(Token.Tag.eof, last_token.tag);
    try std.testing.expectEqual(source.len, last_token.loc.start);
    try std.testing.expectEqual(source.len, last_token.loc.end);
}
