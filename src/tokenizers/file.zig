const std = @import("std");

pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Loc = struct {
        start: usize,
        end: usize,
    };

    pub const Tag = enum {
        string_literal,
        int_literal,
        float_literal,
        l_bracket, // [
        r_bracket, // ]
    };
};

pub const Tokenizer = struct {
    buffer: [:0]const u8,
    index: usize,

    // Maybe change that to use the stream directly so I dont have to read the line 2 times
    pub fn init(buffer: [:0]const u8) Tokenizer {
        // Skip the UTF-8 BOM if present.
        return .{
            .buffer = buffer,
            .index = if (std.mem.startsWith(u8, buffer, "\xEF\xBB\xBF")) 3 else 0, // WTF ? I guess some OS add that or some shit like that
        };
    }

    const State = enum {
        start,
        string_literal,
        float,
        int,
    };

    pub fn getTokenSlice(self: *Tokenizer, token: Token) []const u8 {
        return self.buffer[token.loc.start..token.loc.end];
    }

    pub fn next(self: *Tokenizer) Token {
        // That ugly but work
        if (self.buffer[self.index] == ' ') self.index += 1;

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

            if (self.index == self.buffer.len) break;

            switch (state) {
                .start => switch (c) {
                    '\'' => {
                        state = .string_literal;
                        result.tag = .string_literal;
                    },
                    '0'...'9', '-' => {
                        state = .int;
                        result.tag = .int_literal;
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
                    else => std.debug.print("Unknow character: {c}\n", .{c}),
                },

                .string_literal => switch (c) {
                    '\'' => {
                        self.index += 1;
                        break;
                    },
                    else => continue,
                },

                .int => switch (c) {
                    '.' => {
                        state = .float;
                        result.tag = .float_literal;
                    },
                    '0'...'9' => continue,
                    else => break,
                },
                .float => switch (c) {
                    '0'...'9' => {
                        continue;
                    },
                    else => {
                        break;
                    },
                },
            }
        }

        result.loc.end = self.index;
        return result;
    }
};

test "Basics" {
    try testTokenize("193 88.92 [ 123]   'hello mommy'", &.{ .int_literal, .float_literal, .l_bracket, .int_literal, .r_bracket });
}

fn testTokenize(source: [:0]const u8, expected_token_tags: []const Token.Tag) !void {
    var tokenizer = Tokenizer.init(source);
    for (expected_token_tags) |expected_token_tag| {
        const token = tokenizer.next();
        try std.testing.expectEqual(expected_token_tag, token.tag);
    }
}
