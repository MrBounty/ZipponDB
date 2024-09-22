const std = @import("std");
const Allocator = std.mem.Allocator;
const Tokenizer = @import("ziqlTokenizer.zig").Tokenizer;
const Token = @import("ziqlTokenizer.zig").Token;

// To work now
// GRAB User {}
// GRAB User {name = 'Adrien'}
// GRAB User {name='Adrien' AND age < 30}
// GRAB User [1] {}
// GRAB User [10; name] {age < 30}
//
// For later

const stdout = std.io.getStdOut().writer();

pub const Parser = struct {
    allocator: Allocator,
    toker: *Tokenizer,
    state: State,

    additional_data: AdditionalData,

    // This is the [] part
    pub const AdditionalData = struct {
        entity_count_to_find: usize = 0,
        member_to_find: std.ArrayList(AdditionalDataMember),

        pub fn init(allocator: Allocator) AdditionalData {
            return AdditionalData{ .member_to_find = std.ArrayList(AdditionalDataMember).init(allocator) };
        }

        pub fn deinit(self: *AdditionalData) void {
            // Get all additional data that are in the list to also deinit them
            self.member_to_find.deinit();
        }
    };

    // This is name in: [name]
    // There is an additional data because it can be [friend [1; name]]
    const AdditionalDataMember = struct {
        name: []const u8,
        additional_data: AdditionalData,

        pub fn init(allocator: Allocator, name: []const u8) AdditionalDataMember {
            const additional_data = AdditionalData.init(allocator);
            return AdditionalDataMember{ .name = name, .additional_data = additional_data };
        }
    };

    const State = enum {
        start,
        invalid,
        end,

        // For the additional data
        expect_count_of_entity_to_find,
        expect_semicolon_OR_right_bracket,
        expect_member,
        next_member_OR_end_OR_new_additional_data,
        next_member_OR_end,

        expect_filter,
    };

    pub fn init(allocator: Allocator, toker: *Tokenizer) Parser {
        return Parser{
            .allocator = allocator,
            .toker = toker,
            .state = State.start,
            .additional_data = AdditionalData.init(allocator),
        };
    }

    pub fn deinit(self: *Parser) void {
        // FIXME: I think additionalData inside additionalData are not deinit
        self.additional_data.deinit();
    }

    pub fn parse(self: *Parser) !void {
        var token = self.toker.next();
        while (self.state != State.end) : (token = self.toker.next()) {
            switch (self.state) {
                .start => {
                    switch (token.tag) {
                        .l_bracket => {
                            try self.parse_additional_data(&self.additional_data);
                        },
                        else => {
                            try stdout.print("Found {any}\n", .{token.tag});

                            return;
                        },
                    }
                },
                else => return,
            }
        }
    }

    /// When this function is call, the tokenizer last token retrieved should be [.
    /// Check if an int is here -> check if ; is here -> check if member is here -> check if [ is here -> loop
    pub fn parse_additional_data(self: *Parser, additional_data: *AdditionalData) !void {
        var token = self.toker.next();
        var skip_next = false;
        self.state = State.expect_count_of_entity_to_find;

        while (self.state != State.end) : ({
            token = if (!skip_next) self.toker.next() else token;
            skip_next = false;
        }) {
            switch (self.state) {
                .expect_count_of_entity_to_find => {
                    switch (token.tag) {
                        .number_literal => {
                            const count = std.fmt.parseInt(usize, self.toker.getTokenSlice(token), 10) catch {
                                try stdout.print(
                                    "Error parsing query: {s} need to be a number.",
                                    .{self.toker.getTokenSlice(token)},
                                );
                                self.state = .invalid;
                                continue;
                            };
                            additional_data.entity_count_to_find = count;
                            self.state = .expect_semicolon_OR_right_bracket;
                        },
                        else => {
                            self.state = .expect_member;
                            skip_next = true;
                        },
                    }
                },
                .expect_semicolon_OR_right_bracket => {
                    switch (token.tag) {
                        .semicolon => {
                            self.state = .expect_member;
                        },
                        .r_bracket => {
                            return;
                        },
                        else => {
                            try self.print_error(
                                "Error: Expect ';' or ']'.",
                                &token,
                            );
                            self.state = .invalid;
                        },
                    }
                },
                .expect_member => {
                    switch (token.tag) {
                        .identifier => {
                            // TODO: Check if the member name exist
                            try additional_data.member_to_find.append(
                                AdditionalDataMember.init(
                                    self.allocator,
                                    self.toker.getTokenSlice(token),
                                ),
                            );

                            self.state = .next_member_OR_end_OR_new_additional_data;
                        },
                        else => {
                            try self.print_error(
                                "Error: A member name should be here.",
                                &token,
                            );
                        },
                    }
                },
                .next_member_OR_end_OR_new_additional_data => {
                    switch (token.tag) {
                        .comma => {
                            self.state = .expect_member;
                        },
                        .r_bracket => {
                            return;
                        },
                        .l_bracket => {
                            try self.parse_additional_data(
                                &additional_data.member_to_find.items[additional_data.member_to_find.items.len - 1].additional_data,
                            );
                            self.state = .next_member_OR_end;
                        },
                        else => {
                            try self.print_error(
                                "Error: Expected a comma ',' or the end or a new list of member to return.",
                                &token,
                            );
                        },
                    }
                },
                .next_member_OR_end => {
                    switch (token.tag) {
                        .comma => {
                            try stdout.print("Expected new member\n", .{});
                            self.state = .expect_member;
                        },
                        .r_bracket => {
                            return;
                        },
                        else => {
                            try self.print_error(
                                "Error: Expected a new member name or the end of the list of member name to return.",
                                &token,
                            );
                        },
                    }
                },
                .invalid => {
                    @panic("=)");
                },
                else => {
                    try self.print_error(
                        "Error: Unknow state.",
                        &token,
                    );
                },
            }
        }
    }

    fn print_error(self: *Parser, message: []const u8, token: *Token) !void {
        try stdout.print("\n", .{});
        try stdout.print("{s}\n", .{self.toker.buffer});

        // Calculate the number of spaces needed to reach the start position.
        var spaces: usize = 0;
        while (spaces < token.loc.start) : (spaces += 1) {
            try stdout.print(" ", .{});
        }

        // Print the '^' characters for the error span.
        var i: usize = token.loc.start;
        while (i < token.loc.end) : (i += 1) {
            try stdout.print("^", .{});
        }
        try stdout.print("    \n", .{}); // Align with the message

        try stdout.print("{s}\n", .{message});

        @panic("");
    }
};

test "Test AdditionalData" {
    const allocator = std.testing.allocator;

    var additional_data1 = Parser.AdditionalData.init(allocator);
    additional_data1.entity_count_to_find = 1;
    testAdditionalData("[1]", additional_data1);

    var additional_data2 = Parser.AdditionalData.init(allocator);
    defer additional_data2.deinit();
    try additional_data2.member_to_find.append(
        Parser.AdditionalDataMember.init(
            allocator,
            "name",
        ),
    );
    testAdditionalData("[name]", additional_data2);

    std.debug.print("AdditionalData Parsing OK \n", .{});
}

fn testAdditionalData(source: [:0]const u8, expected_AdditionalData: Parser.AdditionalData) void {
    const allocator = std.testing.allocator;
    var tokenizer = Tokenizer.init(source);
    var additional_data = Parser.AdditionalData.init(allocator);

    _ = tokenizer.next();
    var parser = Parser.init(allocator, &tokenizer);
    parser.parse_additional_data(&additional_data) catch |err| {
        std.debug.print("Error parsing additional data: {any}\n", .{err});
    };

    std.debug.print("{any}\n\n", .{additional_data});

    std.testing.expectEqual(expected_AdditionalData, additional_data) catch {
        std.debug.print("Additional data are not equal for: {s}\n", .{source});
    };

    parser.deinit();
}
