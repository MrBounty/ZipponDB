// From https://github.com/ziglang/zig/blob/master/lib/std/zig/tokenizer.zig
const std = @import("std");

pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Loc = struct {
        start: usize,
        end: usize,
    };

    pub const types = std.StaticStringMap(Tag).initComptime(.{
        .{ "int", .type_int },
        .{ "float", .type_float },
        .{ "str", .type_str },
        .{ "bool", .type_bool },
        .{ "date", .type_date },
    });

    pub fn getType(bytes: []const u8) ?Tag {
        return types.get(bytes);
    }

    pub const Tag = enum {
        eof,
        invalid,

        type_int,
        type_float,
        type_str,
        type_bool,
        type_date,

        identifier,
        l_paren,
        r_paren,
        lr_bracket,
        comma,
        period,
        two_dot,
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
        l_bracket,
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
                        state = .l_bracket;
                    },
                    ',' => {
                        result.tag = .comma;
                        self.index += 1;
                        break;
                    },
                    '.' => {
                        result.tag = .period;
                        self.index += 1;
                        break;
                    },
                    ':' => {
                        result.tag = .two_dot;
                        self.index += 1;
                        break;
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
                        if (Token.getType(self.buffer[result.loc.start..self.index])) |tag| {
                            result.tag = tag;
                        }
                        break;
                    },
                },

                .l_bracket => switch (c) {
                    ']' => {
                        result.tag = .lr_bracket;
                        self.index += 1;
                        break;
                    },
                    else => {
                        state = .invalid;
                    },
                },
            }
        }

        result.loc.end = self.index;
        return result;
    }
};

test "keywords" {
    try testTokenize("int float str date", &.{ .type_int, .type_float, .type_str, .type_date });
}

test "basic query" {
    try testTokenize("User ()", &.{ .identifier, .l_paren, .r_paren });
    try testTokenize("User (name:str)", &.{ .identifier, .l_paren, .identifier, .two_dot, .type_str, .r_paren });
    try testTokenize("User (name:str, email: str, messages:[]Message.from)", &.{
        .identifier,
        .l_paren,
        .identifier,
        .two_dot,
        .type_str,
        .comma,
        .identifier,
        .two_dot,
        .type_str,
        .comma,
        .identifier,
        .two_dot,
        .lr_bracket,
        .identifier,
        .period,
        .identifier,
        .r_paren,
    });
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
