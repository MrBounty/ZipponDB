const std = @import("std");
const schemaEngine = @import("engines/schema.zig");
const DataEngine = @import("engines/file.zig").FileEngine;
const Condition = @import("engines/file.zig").FileEngine.Condition;
const Tokenizer = @import("tokenizers/ziql.zig").Tokenizer;
const Token = @import("tokenizers/ziql.zig").Token;
const UUID = @import("engines/types/uuid.zig").UUID;
const Allocator = std.mem.Allocator;

const stdout = std.io.getStdOut().writer();

fn send(comptime format: []const u8, args: anytype) void {
    stdout.print(format, args) catch |err| {
        std.log.err("Can't send: {any}", .{err});
        stdout.print("\x03\n", .{}) catch {};
    };

    stdout.print("\x03\n", .{}) catch {};
}

pub const Parser = struct {
    allocator: Allocator,
    state: State,
    toker: *Tokenizer,
    data_engine: DataEngine,
    additional_data: AdditionalData,
    struct_name: []const u8 = undefined,

    action: enum { GRAB, ADD, UPDATE, DELETE } = undefined,

    pub fn init(allocator: Allocator, toker: *Tokenizer) Parser {
        // Do I need to init a DataEngine at each Parser, can't I put it in the CLI parser instead ?
        const data_engine = DataEngine.init(allocator, null);
        return Parser{
            .allocator = allocator,
            .toker = toker,
            .state = State.start,
            .data_engine = data_engine,
            .additional_data = AdditionalData.init(allocator),
        };
    }

    pub fn deinit(self: *Parser) void {
        self.additional_data.deinit();
        self.allocator.free(self.struct_name);
    }

    const Options = struct {
        members_for_ordering: std.ArrayList([]const u8), // The list in the right order of member name to use to order the result
        sense_for_ordering: enum { ASC, DESC },
    };

    const State = enum {
        start,
        invalid,
        end,

        // Endpoint
        parse_new_data_and_add_data,
        filter_and_send,

        // For the main parse function
        expect_struct_name,
        expect_filter,
        parse_additional_data,
        expect_filter_or_additional_data,
        expect_new_data,
        expect_right_arrow,

        // For the additional data parser
        expect_count_of_entity_to_find,
        expect_semicolon_OR_right_bracket,
        expect_member,
        expect_comma_OR_r_bracket_OR_l_bracket,
        expect_comma_OR_r_bracket,

        // For the filter parser
        expect_left_condition, // Condition is a struct in DataEngine, it's all info necessary to get a list of UUID usinf DataEngine.getUUIDListUsingCondition
        expect_operation, // Operations are = != < <= > >=
        expect_value,
        expect_ANDOR_OR_end,
        expect_right_uuid_array,

        // For the new data
        expect_equal,
        expect_new_value,
        expect_comma_OR_end,
        add_member_to_map,
        add_array_to_map,
    };

    /// This is the [] part
    /// IDK if saving it into the Parser struct is a good idea
    pub const AdditionalData = struct {
        entity_count_to_find: usize = 0,
        member_to_find: std.ArrayList(AdditionalDataMember),

        pub fn init(allocator: Allocator) AdditionalData {
            return AdditionalData{ .member_to_find = std.ArrayList(AdditionalDataMember).init(allocator) };
        }

        pub fn deinit(self: *AdditionalData) void {
            for (0..self.member_to_find.items.len) |i| {
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

    pub fn parse(self: *Parser) !void {
        var token = self.toker.next();
        var keep_next = false; // Use in the loop to prevent to get the next token when continue. Just need to make it true and it is reset at every loop

        while (self.state != State.end) : ({
            token = if (!keep_next) self.toker.next() else token;
            keep_next = false;
        }) {
            switch (self.state) {
                .start => {
                    switch (token.tag) {
                        .keyword_grab => {
                            self.action = .GRAB;
                            self.state = .expect_struct_name;
                        },
                        .keyword_add => {
                            self.action = .ADD;
                            self.state = .expect_struct_name;
                        },
                        .keyword_update => {
                            self.action = .UPDATE;
                            self.state = .expect_struct_name;
                        },
                        .keyword_delete => {
                            self.action = .DELETE;
                            self.state = .expect_struct_name;
                        },
                        else => {
                            self.printError("Error: Expected action keyword. Available: GRAB ADD DELETE UPDATE", &token);
                            self.state = .end;
                        },
                    }
                },

                .expect_struct_name => {
                    // Check if the struct name is in the schema
                    self.struct_name = try self.allocator.dupe(u8, self.toker.getTokenSlice(token));
                    if (!schemaEngine.isStructNameExists(self.struct_name)) self.printError("Error: struct name not found in schema.", &token);
                    switch (self.action) {
                        .ADD => self.state = .expect_new_data,
                        else => self.state = .expect_filter_or_additional_data,
                    }
                },

                .expect_filter_or_additional_data => {
                    keep_next = true;
                    switch (token.tag) {
                        .l_bracket => self.state = .parse_additional_data,
                        .l_brace => self.state = .filter_and_send,
                        else => self.printError("Error: Expect [ for additional data or { for a filter", &token),
                    }
                },

                .parse_additional_data => {
                    try self.parseAdditionalData(&self.additional_data);
                    self.state = .filter_and_send;
                },

                .filter_and_send => {
                    var array = std.ArrayList(UUID).init(self.allocator);
                    defer array.deinit();
                    try self.parseFilter(&array, self.struct_name, true);
                    self.sendEntity(array.items);
                    self.state = .end;
                },

                .expect_new_data => {
                    switch (token.tag) {
                        .l_paren => {
                            keep_next = true;
                            self.state = .parse_new_data_and_add_data;
                        },
                        else => self.printError("Error: Expecting new data starting with (", &token),
                    }
                },

                .parse_new_data_and_add_data => {
                    switch (self.action) {
                        .ADD => {
                            var data_map = std.StringHashMap([]const u8).init(self.allocator);
                            defer data_map.deinit();
                            self.parseNewData(&data_map);

                            // TODO: Print the list of missing
                            if (!schemaEngine.checkIfAllMemberInMap(self.struct_name, &data_map)) self.printError("Error: Missing member", &token);
                            const uuid = self.data_engine.writeEntity(self.struct_name, data_map) catch {
                                send("ZipponDB error: Couln't write new data to file", .{});
                                continue;
                            };
                            send("Successfully added new {s} with UUID: {s}", .{ self.struct_name, uuid.format_uuid() });
                            self.state = .end;
                        },
                        .UPDATE => {}, // TODO:
                        else => unreachable,
                    }
                },

                else => unreachable,
            }
        }
    }

    // TODO: Use that when I want to return data to the use, need to understand how it's work.
    // I think for now put the ordering using additional data here
    // Maybe to a struct Communicator to handle all communication between use and cli
    fn sendEntity(self: *Parser, uuid_array: []UUID) void {
        _ = self;
        _ = uuid_array;

        //send("Number of uuid to send: {d}\n", .{uuid_array.len});
    }

    // TODO: The parser that check what is between ||
    // For now only |ASC name, age|
    fn parseOptions(self: *Parser) void {
        _ = self;
    }

    /// Take an array of UUID and populate it with what match what is between {}
    /// Main is to know if between {} or (), main is true if between {}, otherwise between () inside {}
    fn parseFilter(self: *Parser, left_array: *std.ArrayList(UUID), struct_name: []const u8, main: bool) !void {
        var token = self.toker.next();
        var keep_next = false;
        self.state = State.expect_left_condition;

        var left_condition = Condition.init(struct_name);
        var curent_operation: enum { and_, or_ } = undefined;

        while (self.state != State.end) : ({
            token = if (!keep_next) self.toker.next() else token;
            keep_next = false;
        }) {
            switch (self.state) {
                .expect_left_condition => {
                    token = self.parseCondition(&left_condition, &token);
                    try self.data_engine.getUUIDListUsingCondition(left_condition, left_array);
                    self.state = State.expect_ANDOR_OR_end;
                    keep_next = true;
                },

                .expect_ANDOR_OR_end => {
                    switch (token.tag) {
                        .r_brace => {
                            if (main) {
                                self.state = State.end;
                            } else {
                                self.printError("Error: Expected } to end main condition or AND/OR to continue it", &token);
                            }
                        },
                        .r_paren => {
                            if (!main) {
                                self.state = State.end;
                            } else {
                                self.printError("Error: Expected ) to end inside condition or AND/OR to continue it", &token);
                            }
                        },
                        .keyword_and => {
                            curent_operation = .and_;
                            self.state = State.expect_right_uuid_array;
                        },
                        .keyword_or => {
                            curent_operation = .or_;
                            self.state = State.expect_right_uuid_array;
                        },
                        else => self.printError("Error: Expected a condition including AND or OR or } or )", &token),
                    }
                },

                .expect_right_uuid_array => {
                    var right_array = std.ArrayList(UUID).init(self.allocator);
                    defer right_array.deinit();

                    switch (token.tag) {
                        .l_paren => try self.parseFilter(&right_array, struct_name, false), // run parserFilter to get the right array
                        .identifier => {
                            var right_condition = Condition.init(struct_name);

                            token = self.parseCondition(&right_condition, &token);
                            keep_next = true;
                            try self.data_engine.getUUIDListUsingCondition(right_condition, &right_array);
                        }, // Create a new condition and compare it
                        else => self.printError("Error: Expecting ( or member name.", &token),
                    }

                    switch (curent_operation) {
                        .and_ => {
                            try AND(left_array, &right_array);
                        },
                        .or_ => {
                            try OR(left_array, &right_array);
                        },
                    }
                    std.debug.print("Token here {any}\n", .{token});
                    self.state = .expect_ANDOR_OR_end;
                },

                else => unreachable,
            }
        }
    }

    /// Parse to get a Condition< Which is a struct that is use by the FileEngine to retreive data.
    /// In the query, it is this part name = 'Bob' or age <= 10
    fn parseCondition(self: *Parser, condition: *Condition, token_ptr: *Token) Token {
        var keep_next = false;
        self.state = .expect_member;
        var token = token_ptr.*;

        while (self.state != State.end) : ({
            token = if (!keep_next) self.toker.next() else token;
            keep_next = false;
        }) {
            switch (self.state) {
                .expect_member => {
                    switch (token.tag) {
                        .identifier => {
                            if (!schemaEngine.isMemberPartOfStruct(condition.struct_name, self.toker.getTokenSlice(token))) {
                                self.printError("Error: Member not part of struct.", &token);
                            }
                            condition.data_type = schemaEngine.memberName2DataType(condition.struct_name, self.toker.getTokenSlice(token)) orelse @panic("Couldn't find the struct and member");
                            condition.member_name = self.toker.getTokenSlice(token);
                            self.state = State.expect_operation;
                        },
                        else => self.printError("Error: Expected member name.", &token),
                    }
                },

                .expect_operation => {
                    switch (token.tag) {
                        .equal => condition.operation = .equal, // =
                        .angle_bracket_left => condition.operation = .inferior, // <
                        .angle_bracket_right => condition.operation = .superior, // >
                        .angle_bracket_left_equal => condition.operation = .inferior_or_equal, // <=
                        .angle_bracket_right_equal => condition.operation = .superior_or_equal, // >=
                        .bang_equal => condition.operation = .different, // !=
                        else => self.printError("Error: Expected condition. Including < > <= >= = !=", &token),
                    }
                    self.state = State.expect_value;
                },

                .expect_value => {
                    switch (condition.data_type) {
                        .int => {
                            switch (token.tag) {
                                .int_literal => condition.value = self.toker.getTokenSlice(token),
                                else => self.printError("Error: Expected int", &token),
                            }
                        },
                        .float => {
                            switch (token.tag) {
                                .float_literal => condition.value = self.toker.getTokenSlice(token),
                                else => self.printError("Error: Expected float", &token),
                            }
                        },
                        .str => {
                            switch (token.tag) {
                                .string_literal => condition.value = self.toker.getTokenSlice(token),
                                else => self.printError("Error: Expected string", &token),
                            }
                        },
                        .bool => {
                            switch (token.tag) {
                                .bool_literal_true, .bool_literal_false => condition.value = self.toker.getTokenSlice(token),
                                else => self.printError("Error: Expected bool", &token),
                            }
                        },
                        .int_array => {
                            const start_index = token.loc.start;
                            token = self.toker.next();
                            while (token.tag != Token.Tag.r_bracket) : (token = self.toker.next()) {
                                switch (token.tag) {
                                    .int_literal => continue,
                                    else => self.printError("Error: Expected int or ].", &token),
                                }
                            }
                            condition.value = self.toker.buffer[start_index..token.loc.end];
                        },
                        .float_array => {
                            const start_index = token.loc.start;
                            token = self.toker.next();
                            while (token.tag != Token.Tag.r_bracket) : (token = self.toker.next()) {
                                switch (token.tag) {
                                    .float_literal => continue,
                                    else => self.printError("Error: Expected float or ].", &token),
                                }
                            }
                            condition.value = self.toker.buffer[start_index..token.loc.end];
                        },
                        .str_array => {
                            const start_index = token.loc.start;
                            token = self.toker.next();
                            while (token.tag != Token.Tag.r_bracket) : (token = self.toker.next()) {
                                switch (token.tag) {
                                    .string_literal => continue,
                                    else => self.printError("Error: Expected string or ].", &token),
                                }
                            }
                            condition.value = self.toker.buffer[start_index..token.loc.end];
                        },
                        .bool_array => {
                            const start_index = token.loc.start;
                            token = self.toker.next();
                            while (token.tag != Token.Tag.r_bracket) : (token = self.toker.next()) {
                                switch (token.tag) {
                                    .bool_literal_false, .bool_literal_true => continue,
                                    else => self.printError("Error: Expected bool or ].", &token),
                                }
                            }
                            condition.value = self.toker.buffer[start_index..token.loc.end];
                        },
                    }
                    self.state = .end;
                },

                else => unreachable,
            }
        }
        return token;
    }

    /// When this function is call, nect token should be [
    /// Check if an int is here -> check if ; is here -> check if member is here -> check if [ is here -> loop
    fn parseAdditionalData(self: *Parser, additional_data: *AdditionalData) !void {
        var token = self.toker.next();
        var keep_next = false;
        self.state = .expect_count_of_entity_to_find;

        while (self.state != .end) : ({
            token = if ((!keep_next) and (self.state != .end)) self.toker.next() else token;
            keep_next = false;
        }) {
            switch (self.state) {
                .expect_count_of_entity_to_find => {
                    switch (token.tag) {
                        .int_literal => {
                            const count = std.fmt.parseInt(usize, self.toker.getTokenSlice(token), 10) catch {
                                self.printError("Error while transforming this into a integer.", &token);
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
                        .semicolon => self.state = .expect_member,
                        .r_bracket => self.state = .end,
                        else => self.printError("Error: Expect ';' or ']'.", &token),
                    }
                },

                .expect_member => {
                    switch (token.tag) {
                        .identifier => {
                            if (!schemaEngine.isMemberNameInStruct(self.struct_name, self.toker.getTokenSlice(token))) self.printError("Member not found in struct.", &token);
                            try additional_data.member_to_find.append(
                                AdditionalDataMember.init(
                                    self.allocator,
                                    self.toker.getTokenSlice(token),
                                ),
                            );

                            self.state = .expect_comma_OR_r_bracket_OR_l_bracket;
                        },
                        else => self.printError("Error: Expected a member name.", &token),
                    }
                },

                .expect_comma_OR_r_bracket_OR_l_bracket => {
                    switch (token.tag) {
                        .comma => self.state = .expect_member,
                        .r_bracket => self.state = .end,
                        .l_bracket => {
                            try self.parseAdditionalData(
                                &additional_data.member_to_find.items[additional_data.member_to_find.items.len - 1].additional_data,
                            );
                            self.state = .expect_comma_OR_r_bracket;
                        },
                        else => self.printError("Error: Expected , or ] or [", &token),
                    }
                },

                .expect_comma_OR_r_bracket => {
                    switch (token.tag) {
                        .comma => self.state = .expect_member,
                        .r_bracket => self.state = .end,
                        else => self.printError("Error: Expected , or ]", &token),
                    }
                },

                else => unreachable,
            }
        }
    }

    /// Take the tokenizer and return a map of the query for the ADD command.
    /// Keys are the member name and value are the string of the value in the query. E.g. 'Adrien' or '10'
    /// Entry token need to be (
    fn parseNewData(self: *Parser, member_map: *std.StringHashMap([]const u8)) void {
        var token = self.toker.next();
        var keep_next = false;
        var member_name: []const u8 = undefined; // Maybe use allocator.alloc
        self.state = .expect_member;

        while (self.state != .end) : ({
            token = if (!keep_next) self.toker.next() else token;
            keep_next = false;
        }) {
            switch (self.state) {
                .expect_member => {
                    switch (token.tag) {
                        .identifier => {
                            member_name = self.toker.getTokenSlice(token);
                            if (!schemaEngine.isMemberNameInStruct(self.struct_name, member_name)) self.printError("Member not found in struct.", &token);
                            self.state = .expect_equal;
                        },
                        else => self.printError("Error: Expected member name.", &token),
                    }
                },

                .expect_equal => {
                    switch (token.tag) {
                        // TODO: Add more comparison like IN or other stuff
                        .equal => self.state = .expect_new_value,
                        else => self.printError("Error: Expected =", &token),
                    }
                },

                .expect_new_value => {
                    const data_type = schemaEngine.memberName2DataType(self.struct_name, member_name);
                    switch (data_type.?) {
                        .int => {
                            switch (token.tag) {
                                .int_literal, .keyword_null => {
                                    member_map.put(member_name, self.toker.getTokenSlice(token)) catch @panic("Could not add member name and value to map in getMapOfMember");
                                    self.state = .expect_comma_OR_end;
                                },
                                else => self.printError("Error: Expected int", &token),
                            }
                        },
                        .float => {
                            switch (token.tag) {
                                .float_literal, .keyword_null => {
                                    member_map.put(member_name, self.toker.getTokenSlice(token)) catch @panic("Could not add member name and value to map in getMapOfMember");
                                    self.state = .expect_comma_OR_end;
                                },
                                else => self.printError("Error: Expected float", &token),
                            }
                        },
                        .bool => {
                            switch (token.tag) {
                                .bool_literal_true => {
                                    member_map.put(member_name, "1") catch @panic("Could not add member name and value to map in getMapOfMember");
                                    self.state = .expect_comma_OR_end;
                                },
                                .bool_literal_false => {
                                    member_map.put(member_name, "0") catch @panic("Could not add member name and value to map in getMapOfMember");
                                    self.state = .expect_comma_OR_end;
                                },
                                .keyword_null => {
                                    member_map.put(member_name, self.toker.getTokenSlice(token)) catch @panic("Could not add member name and value to map in getMapOfMember");
                                    self.state = .expect_comma_OR_end;
                                },
                                else => self.printError("Error: Expected bool: true false", &token),
                            }
                        },
                        .str => {
                            switch (token.tag) {
                                .string_literal, .keyword_null => {
                                    member_map.put(member_name, self.toker.getTokenSlice(token)) catch @panic("Could not add member name and value to map in getMapOfMember");
                                    self.state = .expect_comma_OR_end;
                                },
                                else => self.printError("Error: Expected string between ''", &token),
                            }
                        },
                        // TODO: Maybe upgrade that to use multiple state
                        .int_array => {
                            switch (token.tag) {
                                .l_bracket => {
                                    const start_index = token.loc.start;
                                    token = self.toker.next();
                                    while (token.tag != .r_bracket) : (token = self.toker.next()) {
                                        switch (token.tag) {
                                            .int_literal => continue,
                                            else => self.printError("Error: Expected int or ].", &token),
                                        }
                                    }
                                    // Maybe change that as it just recreate a string that is already in the buffer
                                    member_map.put(member_name, self.toker.buffer[start_index..token.loc.end]) catch @panic("Couln't add string of array in data map");
                                    self.state = .expect_comma_OR_end;
                                },
                                else => self.printError("Error: Expected [ to start an array", &token),
                            }
                        },
                        .float_array => {
                            switch (token.tag) {
                                .l_bracket => {
                                    const start_index = token.loc.start;
                                    token = self.toker.next();
                                    while (token.tag != .r_bracket) : (token = self.toker.next()) {
                                        switch (token.tag) {
                                            .float_literal => continue,
                                            else => self.printError("Error: Expected float or ].", &token),
                                        }
                                    }
                                    // Maybe change that as it just recreate a string that is already in the buffer
                                    member_map.put(member_name, self.toker.buffer[start_index..token.loc.end]) catch @panic("Couln't add string of array in data map");
                                    self.state = .expect_comma_OR_end;
                                },
                                else => self.printError("Error: Expected [ to start an array", &token),
                            }
                        },
                        .bool_array => {
                            switch (token.tag) {
                                .l_bracket => {
                                    const start_index = token.loc.start;
                                    token = self.toker.next();
                                    while (token.tag != .r_bracket) : (token = self.toker.next()) {
                                        switch (token.tag) {
                                            .bool_literal_false, .bool_literal_true => continue,
                                            else => self.printError("Error: Expected bool or ].", &token),
                                        }
                                    }
                                    // Maybe change that as it just recreate a string that is already in the buffer
                                    member_map.put(member_name, self.toker.buffer[start_index..token.loc.end]) catch @panic("Couln't add string of array in data map");
                                    self.state = .expect_comma_OR_end;
                                },
                                else => self.printError("Error: Expected [ to start an array", &token),
                            }
                        },
                        .str_array => {
                            switch (token.tag) {
                                .l_bracket => {
                                    const start_index = token.loc.start;
                                    token = self.toker.next();
                                    while (token.tag != .r_bracket) : (token = self.toker.next()) {
                                        switch (token.tag) {
                                            .string_literal => continue,
                                            else => self.printError("Error: Expected str or ].", &token),
                                        }
                                    }
                                    // Maybe change that as it just recreate a string that is already in the buffer
                                    member_map.put(member_name, self.toker.buffer[start_index..token.loc.end]) catch @panic("Couln't add string of array in data map");
                                    self.state = .expect_comma_OR_end;
                                },
                                else => self.printError("Error: Expected [ to start an array", &token),
                            }
                        },
                    }
                },

                .expect_comma_OR_end => {
                    switch (token.tag) {
                        .r_paren => self.state = .end,
                        .comma => self.state = .expect_member,
                        else => self.printError("Error: Expect , or )", &token),
                    }
                },

                else => unreachable,
            }
        }
    }

    fn printError(self: *Parser, message: []const u8, token: *Token) void {
        stdout.print("\n", .{}) catch {};
        stdout.print("{s}\n", .{self.toker.buffer}) catch {};

        // Calculate the number of spaces needed to reach the start position.
        var spaces: usize = 0;
        while (spaces < token.loc.start) : (spaces += 1) {
            stdout.print(" ", .{}) catch {};
        }

        // Print the '^' characters for the error span.
        var i: usize = token.loc.start;
        while (i < token.loc.end) : (i += 1) {
            stdout.print("^", .{}) catch {};
        }
        stdout.print("    \n", .{}) catch {}; // Align with the message

        stdout.print("{s}\n", .{message}) catch {};

        stdout.print("{any}\n{any}\n", .{ token.tag, token.loc }) catch {};

        send("", .{});
    }
};

// TODO: Optimize both
fn OR(arr1: *std.ArrayList(UUID), arr2: *std.ArrayList(UUID)) !void {
    for (0..arr2.items.len) |i| {
        if (!containUUID(arr1.*, arr2.items[i])) {
            try arr1.append(arr2.items[i]);
        }
    }
}

fn AND(arr1: *std.ArrayList(UUID), arr2: *std.ArrayList(UUID)) !void {
    var i: usize = 0;
    for (0..arr1.items.len) |_| {
        if (!containUUID(arr2.*, arr1.items[i])) {
            _ = arr1.orderedRemove(i);
        } else {
            i += 1;
        }
    }
}

test "OR & AND" {
    const allocator = std.testing.allocator;

    var right_arr = std.ArrayList(UUID).init(allocator);
    defer right_arr.deinit();
    try right_arr.append(try UUID.parse("00000000-0000-0000-0000-000000000000"));
    try right_arr.append(try UUID.parse("00000000-0000-0000-0000-000000000001"));
    try right_arr.append(try UUID.parse("00000000-0000-0000-0000-000000000005"));
    try right_arr.append(try UUID.parse("00000000-0000-0000-0000-000000000006"));
    try right_arr.append(try UUID.parse("00000000-0000-0000-0000-000000000007"));

    var left_arr1 = std.ArrayList(UUID).init(allocator);
    defer left_arr1.deinit();
    try left_arr1.append(try UUID.parse("00000000-0000-0000-0000-000000000000"));
    try left_arr1.append(try UUID.parse("00000000-0000-0000-0000-000000000001"));
    try left_arr1.append(try UUID.parse("00000000-0000-0000-0000-000000000002"));
    try left_arr1.append(try UUID.parse("00000000-0000-0000-0000-000000000003"));
    try left_arr1.append(try UUID.parse("00000000-0000-0000-0000-000000000004"));

    var expected_arr1 = std.ArrayList(UUID).init(allocator);
    defer expected_arr1.deinit();
    try expected_arr1.append(try UUID.parse("00000000-0000-0000-0000-000000000000"));
    try expected_arr1.append(try UUID.parse("00000000-0000-0000-0000-000000000001"));

    try AND(&left_arr1, &right_arr);
    try std.testing.expect(compareUUIDArray(left_arr1, expected_arr1));

    var left_arr2 = std.ArrayList(UUID).init(allocator);
    defer left_arr2.deinit();
    try left_arr2.append(try UUID.parse("00000000-0000-0000-0000-000000000000"));
    try left_arr2.append(try UUID.parse("00000000-0000-0000-0000-000000000001"));
    try left_arr2.append(try UUID.parse("00000000-0000-0000-0000-000000000002"));
    try left_arr2.append(try UUID.parse("00000000-0000-0000-0000-000000000003"));
    try left_arr2.append(try UUID.parse("00000000-0000-0000-0000-000000000004"));

    var expected_arr2 = std.ArrayList(UUID).init(allocator);
    defer expected_arr2.deinit();
    try expected_arr2.append(try UUID.parse("00000000-0000-0000-0000-000000000000"));
    try expected_arr2.append(try UUID.parse("00000000-0000-0000-0000-000000000001"));
    try expected_arr2.append(try UUID.parse("00000000-0000-0000-0000-000000000002"));
    try expected_arr2.append(try UUID.parse("00000000-0000-0000-0000-000000000003"));
    try expected_arr2.append(try UUID.parse("00000000-0000-0000-0000-000000000004"));
    try expected_arr2.append(try UUID.parse("00000000-0000-0000-0000-000000000005"));
    try expected_arr2.append(try UUID.parse("00000000-0000-0000-0000-000000000006"));
    try expected_arr2.append(try UUID.parse("00000000-0000-0000-0000-000000000007"));

    try OR(&left_arr2, &right_arr);

    try std.testing.expect(compareUUIDArray(left_arr2, expected_arr2));
}

fn containUUID(arr: std.ArrayList(UUID), value: UUID) bool {
    return for (arr.items) |elem| {
        if (value.compare(elem)) break true;
    } else false;
}

fn compareUUIDArray(arr1: std.ArrayList(UUID), arr2: std.ArrayList(UUID)) bool {
    if (arr1.items.len != arr2.items.len) {
        std.debug.print("Not same array len when comparing UUID. arr1: {d} arr2: {d}\n", .{ arr1.items.len, arr2.items.len });
        return false;
    }

    for (0..arr1.items.len) |i| {
        if (!containUUID(arr2, arr1.items[i])) return false;
    }

    return true;
}

test "GRAB with additional data" {
    try testParsing("GRAB User [1] {age < 18}");
    try testParsing("GRAB User [name] {age < 18}");
    try testParsing("GRAB User [100; name] {age < 18}");
}

test "GRAB filter with string" {
    // TODO: Use a fixe dataset for testing, to choose in the build.zig
    // It should check if the right number of entity is found too
    try testParsing("GRAB User {name = 'Brittany Rogers'}");
    try testParsing("GRAB User {name != 'Brittany Rogers'}");
}

test "GRAB filter with int" {
    // TODO: Use a fixe dataset for testing, to choose in the build.zig
    // It should check if the right number of entity is found too
    try testParsing("GRAB User {age = 18}");
    try testParsing("GRAB User {age > 18}");
    try testParsing("GRAB User {age < 18}");
    try testParsing("GRAB User {age <= 18}");
    try testParsing("GRAB User {age >= 18}");
    try testParsing("GRAB User {age != 18}");
}

fn testParsing(source: [:0]const u8) !void {
    const allocator = std.testing.allocator;
    var tokenizer = Tokenizer.init(source);
    var parser = Parser.init(allocator, &tokenizer);
    defer parser.deinit();
    try parser.parse();
}

test "Parse condition" {
    const condition1 = Condition{ .data_type = .int, .member_name = "age", .operation = .superior_or_equal, .struct_name = "User", .value = "26" };
    try testConditionParsing("age >= 26", condition1);

    const condition2 = Condition{ .data_type = .int_array, .member_name = "scores", .operation = .equal, .struct_name = "User", .value = "[1 2 42]" };
    try testConditionParsing("scores = [1 2 42]", condition2);

    const condition3 = Condition{ .data_type = .str, .member_name = "email", .operation = .equal, .struct_name = "User", .value = "'adrien@email.com'" };
    try testConditionParsing("email = 'adrien@email.com'", condition3);
}

fn testConditionParsing(source: [:0]const u8, expected_condition: Condition) !void {
    const allocator = std.testing.allocator;
    var tokenizer = Tokenizer.init(source);
    var parser = Parser.init(allocator, &tokenizer);
    var token = tokenizer.next();

    var condition = Condition.init("User");
    _ = parser.parseCondition(&condition, &token);

    try std.testing.expect(compareCondition(expected_condition, condition));
}

fn compareCondition(c1: Condition, c2: Condition) bool {
    return ((std.mem.eql(u8, c1.value, c2.value)) and (std.mem.eql(u8, c1.struct_name, c2.struct_name)) and (std.mem.eql(u8, c1.member_name, c2.member_name)) and (c1.operation == c2.operation) and (c1.data_type == c2.data_type));
}

test "Parse new data" {
    const allocator = std.testing.allocator;

    var map1 = std.StringHashMap([]const u8).init(allocator);
    defer map1.deinit();
    try map1.put("name", "'Adrien'");
    testNewDataParsing("(name = 'Adrien')", map1);

    var map2 = std.StringHashMap([]const u8).init(allocator);
    defer map2.deinit();
    try map2.put("name", "'Adrien'");
    try map2.put("email", "'adrien@email.com'");
    try map2.put("scores", "[1 4 19]");
    try map2.put("age", "26");
    testNewDataParsing("(name = 'Adrien', scores = [1 4 19], age = 26, email = 'adrien@email.com')", map2);
}

fn testNewDataParsing(source: [:0]const u8, expected_member_map: std.StringHashMap([]const u8)) void {
    const allocator = std.testing.allocator;
    var tokenizer = Tokenizer.init(source);

    var parser = Parser.init(allocator, &tokenizer);
    parser.struct_name = allocator.dupe(u8, "User") catch @panic("Cant alloc struct name");
    defer parser.deinit();

    var data_map = std.StringHashMap([]const u8).init(allocator);
    defer data_map.deinit();

    _ = tokenizer.next();
    parser.parseNewData(&data_map);

    var iterator = expected_member_map.iterator();

    var expected_total_count: usize = 0;
    var found_count: usize = 0;
    var error_found = false;
    while (iterator.next()) |entry| {
        expected_total_count += 1;
        if (!data_map.contains(entry.key_ptr.*)) {
            std.debug.print("Error new data parsing: Missing {s} in parsed map.\n", .{entry.key_ptr.*});
            error_found = true;
            continue;
        }
        if (!std.mem.eql(u8, entry.value_ptr.*, data_map.get(entry.key_ptr.*).?)) {
            std.debug.print("Error new data parsing: Wrong data for {s} in parsed map.\n    Expected: {s}\n    Got: {s}", .{ entry.key_ptr.*, entry.value_ptr.*, data_map.get(entry.key_ptr.*).? });
            error_found = true;
            continue;
        }
        found_count += 1;
    }

    if ((error_found) or (expected_total_count != found_count)) @panic("=(");
}

test "Parse filter" {
    const allocator = std.testing.allocator;

    var tokenizer = Tokenizer.init("{name = 'Adrien'}");
    var parser = Parser.init(allocator, &tokenizer);
    parser.struct_name = allocator.dupe(u8, "User") catch @panic("Cant alloc struct name"); // Otherwise get an error trying to free this when deinit

    defer parser.deinit();
    _ = tokenizer.next(); // Start at name

    var uuid_array = std.ArrayList(UUID).init(allocator);
    defer uuid_array.deinit();

    try parser.parseFilter(&uuid_array, "User", true);
}

test "Parse additional data" {
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
            "friends",
        ),
    );
    testAdditionalData("[100; friends [name]]", additional_data4);
}

fn testAdditionalData(source: [:0]const u8, expected_AdditionalData: Parser.AdditionalData) void {
    const allocator = std.testing.allocator;
    var tokenizer = Tokenizer.init(source);

    var parser = Parser.init(allocator, &tokenizer);
    parser.struct_name = allocator.dupe(u8, "User") catch @panic("Cant alloc struct name");
    defer parser.deinit();

    _ = tokenizer.next();
    parser.parseAdditionalData(&parser.additional_data) catch |err| {
        std.debug.print("Error parsing additional data: {any}\n", .{err});
    };

    compareAdditionalData(expected_AdditionalData, parser.additional_data);
}

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

        std.testing.expect(founded) catch {
            std.debug.print("{s} not found\n", .{elem1.name});
            @panic("=(");
        };
    }
}
