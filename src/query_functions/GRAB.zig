const std = @import("std");
const Allocator = std.mem.Allocator;
const ziqlTokenizer = @import("../tokenizers/ziqlTokenizer.zig").Tokenizer;

// To work now
// GRAB User {}
// GRAB User {name = 'Adrien'}
// GRAB User {name='Adrien' AND age < 30}
// GRAB User [1] {}
// GRAB User [10; name] {age < 30}
//
// For later

const stdout = std.io.getStdOut().writer();

const AdditionalData = struct {
    entity_to_find: usize = 0,
    member_to_find: std.ArrayList([]const u8),

    pub fn init(allocator: Allocator) AdditionalData {
        return AdditionalData{ .member_to_find = std.ArrayList(u8).init(allocator) };
    }
};

pub const Parser = struct {
    allocator: Allocator,
    additional_data: AdditionalData,
    toker: *ziqlTokenizer,
    state: State,

    const State = enum {
        start,
        invalid,
        end,

        expect_additional_data,
        expect_count_of_entity_to_find,
        expect_semicolon,

        expect_filter,
    };

    pub fn init(allocator: Allocator, toker: *ziqlTokenizer) Parser {
        return Parser{ .allocator = allocator, .toker = toker, .state = State.expect_additional_data, .additional_data = AdditionalData.init(allocator) };
    }

    pub fn deinit(self: *Parser) void {
        self.additional_data.member_to_find.deinit();
    }

    pub fn parse_additional_data(self: *Parser) !void {
        var token = self.toker.next();
        while (self.state != State.end) : (token = self.toker.next()) {
            switch (self.state) {
                .expect_additional_data => {
                    switch (token.tag) {
                        .l_bracket => {
                            try stdout.print("Additional data found.\n", .{});
                            self.state = State.expect_count_of_entity_to_find;
                        },
                        else => {
                            try stdout.print("No additional data found.\n", .{});
                            self.state = State.expect_filter;
                        },
                    }
                },
                .expect_count_of_entity_to_find => {
                    switch (token.tag) {
                        .number_literal => {
                            try stdout.print("Count of entity found.\n", .{});
                            self.state = State.expect_semicolon;
                        },
                        else => {
                            try stdout.print("No count of entity found.\n", .{});
                            self.state = State.expect_filter;
                        },
                    }
                },
                .expect_semicolon => {
                    switch (token.tag) {
                        .semicolon => {
                            try stdout.print("Found semiconlon.\n", .{});
                            self.state = State.expect_semicolon;
                        },
                        else => {
                            try stdout.print("Expected semicon here: {s}.\n", .{self.toker.buffer[token.loc.start - 5 .. token.loc.end + 5]});
                            self.state = State.invalid;
                        },
                    }
                },
                .invalid => {
                    return;
                },
                else => {
                    try stdout.print("End\n", .{});
                },
            }
        }
    }
};
