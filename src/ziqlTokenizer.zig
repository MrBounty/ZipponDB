// From https://github.com/ziglang/zig/blob/master/lib/std/zig/tokenizer.zig
const std = @import("std");

pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Loc = struct {
        start: usize,
        end: usize,
    };

    pub const keywords = std.StaticStringMap(Tag).initComptime(.{
        .{ "GRAB", .keyword_grab },
        .{ "UPDATE", .keyword_update },
        .{ "DELETE", .keyword_delete },
        .{ "ADD", .keyword_add },
        .{ "IN", .keyword_in },
        .{ "null", .keyword_null },
        .{ "__DESCRIBE__", .keyword__describe__ },
        .{ "__INIT__", .keyword__init__ },
    });

    pub fn getKeyword(bytes: []const u8) ?Tag {
        return keywords.get(bytes);
    }

    pub const Tag = enum {
        eof,
        invalid,

        keyword_grab,
        keyword_update,
        keyword_delete,
        keyword_add,
        keyword_in,
        keyword_null,
        keyword__describe__,
        keyword__init__,

        string_literal,
        number_literal,
        identifier,
        equal,
        bang,
        pipe,
        l_paren,
        r_paren,
        l_bracket,
        r_bracket,
        l_brace,
        r_brace,
        semicolon,
        comma,
        angle_bracket_left,
        angle_bracket_right,
        angle_bracket_left_equal,
        angle_bracket_right_equal,
        equal_angle_bracket_right,
        period,
        bang_equal,
    };
};

pub const Tokenizer = struct {
    buffer: [:0]const u8,
    index: usize,

    pub fn getTokenSlice(self: *Tokenizer, token: Token) []const u8 {
        return self.buffer[token.loc.start..token.loc.end];
    }

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
        string_literal,
        identifier,
        equal,
        bang,
        angle_bracket_left,
        angle_bracket_right,
        string_literal_backslash,
        int_exponent,
        int_period,
        float,
        float_exponent,
        int,
    };

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
                    '\'' => {
                        state = .string_literal;
                        result.tag = .string_literal;
                    },
                    'a'...'z', 'A'...'Z', '_' => {
                        state = .identifier;
                        result.tag = .identifier;
                    },
                    '=' => {
                        state = .equal;
                    },
                    '!' => {
                        state = .bang;
                    },
                    '|' => {
                        result.tag = .pipe;
                        self.index += 1;
                        break;
                    },
                    '(' => {
                        result.tag = .l_paren;
                        self.index += 1;
                        break;
                    },
                    ')' => {
                        result.tag = .r_paren;
                        self.index += 1;
                        break;
                    },
                    '[' => {
                        result.tag = .l_bracket;
                        self.index += 1;
                        break;
                    },
                    ']' => {
                        result.tag = .r_bracket;
                        self.index += 1;
                        break;
                    },
                    ';' => {
                        result.tag = .semicolon;
                        self.index += 1;
                        break;
                    },
                    ',' => {
                        result.tag = .comma;
                        self.index += 1;
                        break;
                    },
                    '<' => {
                        state = .angle_bracket_left;
                    },
                    '>' => {
                        state = .angle_bracket_right;
                    },
                    '{' => {
                        result.tag = .l_brace;
                        self.index += 1;
                        break;
                    },
                    '}' => {
                        result.tag = .r_brace;
                        self.index += 1;
                        break;
                    },
                    '.' => {
                        result.tag = .period;
                        self.index += 1;
                        break;
                    },
                    '0'...'9' => {
                        state = .int;
                        result.tag = .number_literal;
                    },
                    else => {
                        state = .invalid;
                    },
                },

                .invalid => {
                    // TODO make a better invalid handler
                    @panic("Unknow char!!!");
                },

                .identifier => switch (c) {
                    'a'...'z', 'A'...'Z', '_', '0'...'9' => continue,
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
                    '\'' => {
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

                .bang => switch (c) {
                    '=' => {
                        result.tag = .bang_equal;
                        self.index += 1;
                        break;
                    },
                    //TODO Add the !IN
                    else => {
                        result.tag = .bang;
                        break;
                    },
                },

                .equal => switch (c) {
                    '>' => {
                        result.tag = .equal_angle_bracket_right;
                        self.index += 1;
                        break;
                    },
                    else => {
                        result.tag = .equal;
                        break;
                    },
                },

                .angle_bracket_left => switch (c) {
                    '=' => {
                        result.tag = .angle_bracket_left_equal;
                        self.index += 1;
                        break;
                    },
                    else => {
                        result.tag = .angle_bracket_left;
                        break;
                    },
                },

                .angle_bracket_right => switch (c) {
                    '=' => {
                        result.tag = .angle_bracket_right_equal;
                        self.index += 1;
                        break;
                    },
                    else => {
                        result.tag = .angle_bracket_right;
                        break;
                    },
                },

                .int => switch (c) {
                    '.' => state = .int_period,
                    '_', 'a'...'d', 'f'...'o', 'q'...'z', 'A'...'D', 'F'...'O', 'Q'...'Z', '0'...'9' => continue,
                    'e', 'E', 'p', 'P' => state = .int_exponent,
                    else => break,
                },
                .int_exponent => switch (c) {
                    '-', '+' => {
                        state = .float;
                    },
                    else => {
                        self.index -= 1;
                        state = .int;
                    },
                },
                .int_period => switch (c) {
                    '_', 'a'...'d', 'f'...'o', 'q'...'z', 'A'...'D', 'F'...'O', 'Q'...'Z', '0'...'9' => {
                        state = .float;
                    },
                    'e', 'E', 'p', 'P' => state = .float_exponent,
                    else => {
                        self.index -= 1;
                        break;
                    },
                },
                .float => switch (c) {
                    '_', 'a'...'d', 'f'...'o', 'q'...'z', 'A'...'D', 'F'...'O', 'Q'...'Z', '0'...'9' => continue,
                    'e', 'E', 'p', 'P' => state = .float_exponent,
                    else => break,
                },
                .float_exponent => switch (c) {
                    '-', '+' => state = .float,
                    else => {
                        self.index -= 1;
                        state = .float;
                    },
                },
            }
        }

        result.loc.end = self.index;
        return result;
    }
};

test "keywords" {
    try testTokenize("GRAB UPDATE ADD DELETE IN", &.{ .keyword_grab, .keyword_update, .keyword_add, .keyword_delete, .keyword_in });
}

test "basic query" {
    try testTokenize("GRAB User {}", &.{ .keyword_grab, .identifier, .l_brace, .r_brace });
    try testTokenize("GRAB User { name = 'Adrien'}", &.{ .keyword_grab, .identifier, .l_brace, .identifier, .equal, .string_literal, .r_brace });
    try testTokenize("GRAB User [1; name] {}", &.{ .keyword_grab, .identifier, .l_bracket, .number_literal, .semicolon, .identifier, .r_bracket, .l_brace, .r_brace });
    try testTokenize("GRAB User{}|ASCENDING name|", &.{ .keyword_grab, .identifier, .l_brace, .r_brace, .pipe, .identifier, .identifier, .pipe });
    try testTokenize("DELETE User[1]{name='Adrien'}|ASCENDING name, age|", &.{ .keyword_delete, .identifier, .l_bracket, .number_literal, .r_bracket, .l_brace, .identifier, .equal, .string_literal, .r_brace, .pipe, .identifier, .identifier, .comma, .identifier, .pipe });
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
