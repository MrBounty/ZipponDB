const std = @import("std");
const metadata = @import("metadata.zig");
const Allocator = std.mem.Allocator;
const Tokenizer = @import("ziqlTokenizer.zig").Tokenizer;
const Token = @import("ziqlTokenizer.zig").Token;
const DataEngine = @import("dataEngine.zig").DataEngine;
const UUID = @import("uuid.zig").UUID;

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
    arena: std.heap.ArenaAllocator,
    allocator: Allocator,
    toker: *Tokenizer,
    state: State,

    additional_data: AdditionalData,

    pub fn init(allocator: Allocator, toker: *Tokenizer) Parser {
        var arena = std.heap.ArenaAllocator.init(allocator);
        return Parser{
            .arena = arena,
            .allocator = arena.allocator(),
            .toker = toker,
            .state = State.start,
            .additional_data = AdditionalData.init(allocator),
        };
    }

    pub fn deinit(self: *Parser) void {
        self.additional_data.deinit();
        self.arena.deinit();
    }

    // This is the [] part
    pub const AdditionalData = struct {
        entity_count_to_find: usize = 0,
        member_to_find: std.ArrayList(AdditionalDataMember),

        pub fn init(allocator: Allocator) AdditionalData {
            return AdditionalData{ .member_to_find = std.ArrayList(AdditionalDataMember).init(allocator) };
        }

        pub fn deinit(self: *AdditionalData) void {
            for (0..self.member_to_find.items.len) |i| {
                std.debug.print("{d}\n", .{i});
                self.member_to_find.items[i].additional_data.deinit();
            }

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

        // For the main parse function
        expect_filter,

        // For the additional data parser
        expect_count_of_entity_to_find,
        expect_semicolon_OR_right_bracket,
        expect_member,
        next_member_OR_end_OR_new_additional_data,
        next_member_OR_end,

        // For the filter parser
        expect_condition,
    };

    pub fn parse(self: *Parser) !void {
        var data_engine = DataEngine.init(self.allocator, null);
        defer data_engine.deinit();

        var struct_name_token = self.toker.next();
        if (!self.isStructInSchema(self.toker.getTokenSlice(struct_name_token))) {
            try self.printError("Error: Struct name not in current shema.", &struct_name_token);
            return;
        }

        var token = self.toker.next();
        var keep_next = false;

        while (self.state != State.end) : ({
            token = if (!keep_next) self.toker.next() else token;
            keep_next = false;
        }) {
            switch (self.state) {
                .start => {
                    switch (token.tag) {
                        .l_bracket => {
                            try self.parseAdditionalData(&self.additional_data);
                            self.state = State.expect_filter;
                        },
                        .l_brace => {
                            self.state = State.expect_filter;
                            keep_next = true;
                        },
                        else => {
                            try self.printError("Error: Expected filter starting with {} or what to return starting with []", &token);
                            return;
                        },
                    }
                },
                .expect_filter => {
                    var array = std.ArrayList(UUID).init(self.allocator);
                    try self.parseFilter(&array, struct_name_token);
                    self.state = State.end;
                },
                else => return,
            }
        }
    }

    fn parseFilter(self: *Parser, left_array: *std.ArrayList(UUID), struct_name_token: Token) !void {
        const right_array = std.ArrayList(UUID).init(self.allocator);
        var token = self.toker.next();
        var keep_next = false;
        self.state = State.expect_member;

        _ = right_array;
        _ = left_array;

        while (self.state != State.end) : ({
            token = if (!keep_next) self.toker.next() else token;
            keep_next = false;
        }) {
            switch (self.state) {
                .expect_member => {
                    if (!self.isMemberPartOfStruct(self.toker.getTokenSlice(struct_name_token), self.toker.getTokenSlice(token))) {
                        try self.printError("Error: Member not part of struct.", &token);
                    }
                    self.state = State.expect_condition;
                },
                else => return,
            }
        }
    }

    /// When this function is call, the tokenizer last token retrieved should be [.
    /// Check if an int is here -> check if ; is here -> check if member is here -> check if [ is here -> loop
    pub fn parseAdditionalData(self: *Parser, additional_data: *AdditionalData) !void {
        var token = self.toker.next();
        var keep_next = false;
        self.state = State.expect_count_of_entity_to_find;

        while (self.state != State.end) : ({
            token = if (!keep_next) self.toker.next() else token;
            keep_next = false;
        }) {
            switch (self.state) {
                .expect_count_of_entity_to_find => {
                    switch (token.tag) {
                        .number_literal => {
                            const count = std.fmt.parseInt(usize, self.toker.getTokenSlice(token), 10) catch {
                                try self.printError("Error while transforming this into a integer.", &token);
                                self.state = .invalid;
                                continue;
                            };
                            additional_data.entity_count_to_find = count;
                            self.state = .expect_semicolon_OR_right_bracket;
                        },
                        else => {
                            self.state = .expect_member;
                            keep_next = true;
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
                            try self.printError(
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
                            try self.printError(
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
                            try self.parseAdditionalData(
                                &additional_data.member_to_find.items[additional_data.member_to_find.items.len - 1].additional_data,
                            );
                            self.state = .next_member_OR_end;
                        },
                        else => {
                            try self.printError(
                                "Error: Expected a comma ',' or the end or a new list of member to return.",
                                &token,
                            );
                        },
                    }
                },
                .next_member_OR_end => {
                    switch (token.tag) {
                        .comma => {
                            self.state = .expect_member;
                        },
                        .r_bracket => {
                            return;
                        },
                        else => {
                            try self.printError(
                                "Error: Expected a comma or the end of the list of member name to return.",
                                &token,
                            );
                        },
                    }
                },
                .invalid => {
                    @panic("=)");
                },
                else => {
                    try self.printError(
                        "Error: Unknow state.",
                        &token,
                    );
                },
            }
        }
    }

    fn printError(self: *Parser, message: []const u8, token: *Token) !void {
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

    /// Take a struct name and a member name and return true if the member name is part of the struct
    fn isMemberPartOfStruct(_: *Parser, struct_name: []const u8, member_name: []const u8) bool {
        const all_struct_member = metadata.structName2structMembers(struct_name);

        for (all_struct_member) |key| {
            if (std.mem.eql(u8, key, member_name)) return true;
        }

        return false;
    }

    /// Check if a string is a name of a struct in the currently use engine
    fn isStructInSchema(_: *Parser, struct_name_to_check: []const u8) bool {
        for (metadata.struct_name_list) |struct_name| {
            if (std.mem.eql(u8, struct_name_to_check, struct_name)) {
                return true;
            }
        }
        return false;
    }
};

// TODO: Optimize. Maybe just do a new list and return it instead
fn OR(arr1: *std.ArrayList(UUID), arr2: *std.ArrayList(UUID)) std.ArrayList(UUID) {
    defer arr1.deinit();
    defer arr2.deinit();

    var arr = try arr1.clone();

    for (0..arr2.items.len) |i| {
        if (!arr.contains(arr2[i])) {
            arr.append(arr2[i]);
        }
    }

    return arr;
}

fn AND(arr1: *std.ArrayList(UUID), arr2: *std.ArrayList(UUID)) std.ArrayList(UUID) {
    defer arr1.deinit();
    defer arr2.deinit();

    var arr = try arr1.clone();

    for (0..arr1.items.len) |i| {
        if (arr2.contains(arr1[i])) {
            arr.append(arr1[i]);
        }
    }

    return arr;
}

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

    var additional_data3 = Parser.AdditionalData.init(allocator);
    additional_data3.entity_count_to_find = 1;
    defer additional_data3.deinit();
    try additional_data3.member_to_find.append(
        Parser.AdditionalDataMember.init(
            allocator,
            "name",
        ),
    );
    testAdditionalData("[1; name]", additional_data3);

    var additional_data4 = Parser.AdditionalData.init(allocator);
    additional_data4.entity_count_to_find = 100;
    defer additional_data4.deinit();
    try additional_data4.member_to_find.append(
        Parser.AdditionalDataMember.init(
            allocator,
            "friend",
        ),
    );
    testAdditionalData("[100; friend [name]]", additional_data4);
}

fn testAdditionalData(source: [:0]const u8, expected_AdditionalData: Parser.AdditionalData) void {
    const allocator = std.testing.allocator;
    var tokenizer = Tokenizer.init(source);
    var data_engine = DataEngine.init(allocator);
    defer data_engine.deinit();

    var parser = Parser.init(allocator, &tokenizer, &data_engine);

    defer parser.deinit();
    _ = tokenizer.next();
    parser.parse_additional_data(&parser.additional_data) catch |err| {
        std.debug.print("Error parsing additional data: {any}\n", .{err});
    };

    compareAdditionalData(expected_AdditionalData, parser.additional_data);
}

// TODO: Check AdditionalData inside AdditionalData
fn compareAdditionalData(ad1: Parser.AdditionalData, ad2: Parser.AdditionalData) void {
    std.testing.expectEqual(ad1.entity_count_to_find, ad2.entity_count_to_find) catch {
        std.debug.print("Additional data entity_count_to_find are not equal.\n", .{});
    };

    var founded = false;

    for (ad1.member_to_find.items) |elem1| {
        founded = false;
        for (ad2.member_to_find.items) |elem2| {
            if (std.mem.eql(u8, elem1.name, elem2.name)) {
                compareAdditionalData(elem1.additional_data, elem2.additional_data);
                founded = true;
                break;
            }
        }

        if (!founded) @panic("Member not found");
    }
}
