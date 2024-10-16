const std = @import("std");
const Allocator = std.mem.Allocator;
const FileEngine = @import("fileEngine.zig").FileEngine;
const Condition = @import("fileEngine.zig").FileEngine.Condition;
const Tokenizer = @import("tokenizers/ziql.zig").Tokenizer;
const Token = @import("tokenizers/ziql.zig").Token;
const UUID = @import("types/uuid.zig").UUID;
const AND = @import("types/uuid.zig").AND;
const OR = @import("types/uuid.zig").OR;
const AdditionalData = @import("stuffs/additionalData.zig").AdditionalData;
const AdditionalDataMember = @import("stuffs/additionalData.zig").AdditionalDataMember;
const send = @import("stuffs/utils.zig").send;
const printError = @import("stuffs/utils.zig").printError;

const ZiQlParserError = error{
    SynthaxError,
    MemberNotFound,
    MemberMissing,
    StructNotFound,
    FeatureMissing,
    ParsingValueError,
    ConditionError,
};

const State = enum {
    start,
    invalid,
    end,

    // Endpoint
    parse_new_data_and_add_data,
    filter_and_send,
    filter_and_update,
    filter_and_delete,

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
    expect_left_condition, // Condition is a struct in FileEngine, it's all info necessary to get a list of UUID usinf FileEngine.getUUIDListUsingCondition
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

pub const Parser = struct {
    allocator: Allocator,
    state: State,
    toker: *Tokenizer,
    additional_data: AdditionalData,
    struct_name: []const u8 = undefined,
    file_engine: *FileEngine,

    action: enum { GRAB, ADD, UPDATE, DELETE } = undefined,

    pub fn init(allocator: Allocator, toker: *Tokenizer, file_engine: *FileEngine) Parser {
        // Do I need to init a FileEngine at each Parser, can't I put it in the CLI parser instead ?
        return Parser{
            .allocator = allocator,
            .toker = toker,
            .state = .start,
            .additional_data = AdditionalData.init(allocator),
            .file_engine = file_engine,
        };
    }

    pub fn deinit(self: *Parser) void {
        self.additional_data.deinit();
        self.allocator.free(self.struct_name);
    }

    // TODO: Update to use ASC and DESC
    // Maybe create a Sender struct or something like that
    fn sendEntity(self: *Parser, uuid_list: *std.ArrayList(UUID)) void {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        // Pop some element if the array is too long
        if ((self.additional_data.entity_count_to_find != 0) and (self.additional_data.entity_count_to_find < uuid_list.items.len)) {
            const to_pop = uuid_list.items.len - self.additional_data.entity_count_to_find;
            for (0..to_pop) |_| _ = uuid_list.pop();
        }

        // Im gonna need a function in the file engine to parse and write in the buffer
        self.file_engine.parseAndWriteToSend(self.struct_name, uuid_list.items, &buffer, self.additional_data) catch @panic("Error parsing data to send");

        send("{s}", .{buffer.items});
    }

    pub fn parse(self: *Parser) !void {
        var token = self.toker.next();
        var keep_next = false; // Use in the loop to prevent to get the next token when continue. Just need to make it true and it is reset at every loop

        while (self.state != State.end) : ({
            token = if (!keep_next) self.toker.next() else token;
            keep_next = false;
        }) switch (self.state) {
            .start => switch (token.tag) {
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
                else => return printError("Error: Expected action keyword. Available: GRAB ADD DELETE UPDATE", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
            },

            .expect_struct_name => {
                // Check if the struct name is in the schema
                self.struct_name = try self.allocator.dupe(u8, self.toker.getTokenSlice(token));
                if (token.tag != .identifier) return printError("Error: Missing struct name", ZiQlParserError.StructNotFound, self.toker.buffer, token.loc.start, token.loc.end);
                if (!self.file_engine.isStructNameExists(self.struct_name)) return printError("Error: struct name not found in schema.", ZiQlParserError.StructNotFound, self.toker.buffer, token.loc.start, token.loc.end);
                switch (self.action) {
                    .ADD => self.state = .expect_new_data,
                    else => self.state = .expect_filter_or_additional_data,
                }
            },

            .expect_filter_or_additional_data => {
                keep_next = true;
                switch (token.tag) {
                    .l_bracket => self.state = .parse_additional_data,
                    .l_brace => self.state = switch (self.action) {
                        .GRAB => .filter_and_send,
                        .UPDATE => .filter_and_update,
                        .DELETE => .filter_and_delete,
                        else => unreachable,
                    },
                    .eof => self.state = .filter_and_send,
                    else => return printError("Error: Expect [ for additional data or { for a filter", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
                }
            },

            .parse_additional_data => {
                try self.parseAdditionalData(&self.additional_data);
                self.state = switch (self.action) {
                    .GRAB => .filter_and_send,
                    .UPDATE => .filter_and_update,
                    .DELETE => .filter_and_delete,
                    else => unreachable,
                };
            },

            .filter_and_send => switch (token.tag) {
                .l_brace => {
                    var array = std.ArrayList(UUID).init(self.allocator);
                    defer array.deinit();
                    _ = try self.parseFilter(&array, self.struct_name, true);

                    self.sendEntity(&array);
                    self.state = .end;
                },
                .eof => {
                    var array = std.ArrayList(UUID).init(self.allocator);
                    defer array.deinit();
                    try self.file_engine.getAllUUIDList(self.struct_name, &array);

                    self.sendEntity(&array);
                    self.state = .end;
                },
                else => return printError("Error: Expected filter.", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
            },

            // TODO: Optimize so it doesnt use parseFilter but just parse the file and directly check the condition. Here I end up parsing 2 times.
            .filter_and_update => switch (token.tag) {
                .l_brace => {
                    var array = std.ArrayList(UUID).init(self.allocator);
                    defer array.deinit();
                    token = try self.parseFilter(&array, self.struct_name, true);

                    if (token.tag != .keyword_to) return printError("Error: Expected TO", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end);

                    token = self.toker.next();
                    if (token.tag != .l_paren) return printError("Error: Expected (", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end);

                    var data_map = std.StringHashMap([]const u8).init(self.allocator);
                    defer data_map.deinit();
                    try self.parseNewData(&data_map);

                    try self.file_engine.updateEntities(self.struct_name, array.items, data_map);
                    self.state = .end;
                },
                .keyword_to => {
                    var array = std.ArrayList(UUID).init(self.allocator);
                    defer array.deinit();
                    try self.file_engine.getAllUUIDList(self.struct_name, &array);

                    token = self.toker.next();
                    if (token.tag != .l_paren) return printError("Error: Expected (", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end);

                    var data_map = std.StringHashMap([]const u8).init(self.allocator);
                    defer data_map.deinit();
                    try self.parseNewData(&data_map);

                    try self.file_engine.updateEntities(self.struct_name, array.items, data_map);
                    self.state = .end;
                },
                else => return printError("Error: Expected filter or TO.", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
            },

            .filter_and_delete => switch (token.tag) {
                .l_brace => {
                    var array = std.ArrayList(UUID).init(self.allocator);
                    defer array.deinit();
                    _ = try self.parseFilter(&array, self.struct_name, true);

                    const deleted_count = try self.file_engine.deleteEntities(self.struct_name, array.items);
                    std.debug.print("Successfully deleted {d} {s}\n", .{ deleted_count, self.struct_name });
                    self.state = .end;
                },
                .eof => {
                    var array = std.ArrayList(UUID).init(self.allocator);
                    defer array.deinit();
                    try self.file_engine.getAllUUIDList(self.struct_name, &array);

                    const deleted_count = try self.file_engine.deleteEntities(self.struct_name, array.items);
                    std.debug.print("Successfully deleted all {d} {s}\n", .{ deleted_count, self.struct_name });
                    self.state = .end;
                },
                else => return printError("Error: Expected filter.", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
            },

            .expect_new_data => switch (token.tag) {
                .l_paren => {
                    keep_next = true;
                    self.state = .parse_new_data_and_add_data;
                },
                else => return printError("Error: Expected new data starting with (", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
            },

            .parse_new_data_and_add_data => {
                var data_map = std.StringHashMap([]const u8).init(self.allocator);
                defer data_map.deinit();
                try self.parseNewData(&data_map);

                // TODO: Print the entire list of missing
                if (!self.file_engine.checkIfAllMemberInMap(self.struct_name, &data_map)) return printError("Error: Missing member", ZiQlParserError.MemberMissing, self.toker.buffer, token.loc.start, token.loc.end);
                const uuid = self.file_engine.writeEntity(self.struct_name, data_map) catch {
                    send("ZipponDB error: Couln't write new data to file", .{});
                    continue;
                };
                send("Successfully added new {s} with UUID: {s}", .{ self.struct_name, uuid.format_uuid() });
                self.state = .end;
            },

            else => unreachable,
        };
    }

    /// Take an array of UUID and populate it with what match what is between {}
    /// Main is to know if between {} or (), main is true if between {}, otherwise between () inside {}
    /// TODO: Optimize this so it can use multiple condition at the same time instead of parsing the all file for each condition
    fn parseFilter(self: *Parser, left_array: *std.ArrayList(UUID), struct_name: []const u8, main: bool) !Token {
        var token = self.toker.next();
        var keep_next = false;
        self.state = State.expect_left_condition;

        var left_condition = Condition.init(struct_name);
        var curent_operation: enum { and_, or_ } = undefined;

        while (self.state != State.end) : ({
            token = if (!keep_next) self.toker.next() else token;
            keep_next = false;
        }) switch (self.state) {
            .expect_left_condition => switch (token.tag) {
                .r_brace => {
                    try self.file_engine.getAllUUIDList(struct_name, left_array);
                    self.state = .end;
                },
                else => {
                    token = try self.parseCondition(&left_condition, &token);
                    try self.file_engine.getUUIDListUsingCondition(left_condition, left_array);
                    self.state = .expect_ANDOR_OR_end;
                    keep_next = true;
                },
            },

            .expect_ANDOR_OR_end => switch (token.tag) {
                .r_brace => if (main) {
                    self.state = .end;
                } else {
                    return printError("Error: Expected } to end main condition or AND/OR to continue it", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end);
                },
                .r_paren => if (!main) {
                    self.state = .end;
                } else {
                    return printError("Error: Expected ) to end inside condition or AND/OR to continue it", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end);
                },
                .keyword_and => {
                    curent_operation = .and_;
                    self.state = .expect_right_uuid_array;
                },
                .keyword_or => {
                    curent_operation = .or_;
                    self.state = .expect_right_uuid_array;
                },
                else => return printError("Error: Expected a condition including AND OR or the end of the filter with } or )", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
            },

            .expect_right_uuid_array => {
                var right_array = std.ArrayList(UUID).init(self.allocator);
                defer right_array.deinit();

                switch (token.tag) {
                    .l_paren => _ = try self.parseFilter(&right_array, struct_name, false), // run parserFilter to get the right array
                    .identifier => {
                        var right_condition = Condition.init(struct_name);

                        token = try self.parseCondition(&right_condition, &token);
                        keep_next = true;
                        try self.file_engine.getUUIDListUsingCondition(right_condition, &right_array);
                    }, // Create a new condition and compare it
                    else => return printError("Error: Expected ( or member name.", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
                }

                switch (curent_operation) {
                    .and_ => {
                        try AND(left_array, &right_array);
                    },
                    .or_ => {
                        try OR(left_array, &right_array);
                    },
                }
                self.state = .expect_ANDOR_OR_end;
            },

            else => unreachable,
        };

        return token;
    }

    /// Parse to get a Condition. Which is a struct that is use by the FileEngine to retreive data.
    /// In the query, it is this part name = 'Bob' or age <= 10
    fn parseCondition(self: *Parser, condition: *Condition, token_ptr: *Token) !Token {
        var keep_next = false;
        self.state = .expect_member;
        var token = token_ptr.*;

        while (self.state != State.end) : ({
            token = if (!keep_next) self.toker.next() else token;
            keep_next = false;
        }) switch (self.state) {
            .expect_member => switch (token.tag) {
                .identifier => {
                    if (!self.file_engine.isMemberNameInStruct(condition.struct_name, self.toker.getTokenSlice(token))) {
                        return printError("Error: Member not part of struct.", ZiQlParserError.MemberNotFound, self.toker.buffer, token.loc.start, token.loc.end);
                    }
                    condition.data_type = self.file_engine.memberName2DataType(condition.struct_name, self.toker.getTokenSlice(token)) orelse @panic("Couldn't find the struct and member");
                    condition.member_name = self.toker.getTokenSlice(token);
                    self.state = State.expect_operation;
                },
                else => return printError("Error: Expected member name.", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
            },

            .expect_operation => {
                switch (token.tag) {
                    .equal => condition.operation = .equal, // =
                    .angle_bracket_left => condition.operation = .inferior, // <
                    .angle_bracket_right => condition.operation = .superior, // >
                    .angle_bracket_left_equal => condition.operation = .inferior_or_equal, // <=
                    .angle_bracket_right_equal => condition.operation = .superior_or_equal, // >=
                    .bang_equal => condition.operation = .different, // !=
                    else => return printError("Error: Expected condition. Including < > <= >= = !=", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
                }
                self.state = State.expect_value;
            },

            .expect_value => {
                switch (condition.data_type) {
                    .int => {
                        switch (token.tag) {
                            .int_literal => condition.value = self.toker.getTokenSlice(token),
                            else => return printError("Error: Expected int", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
                        }
                    },
                    .float => {
                        switch (token.tag) {
                            .float_literal => condition.value = self.toker.getTokenSlice(token),
                            else => return printError("Error: Expected float", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
                        }
                    },
                    .str, .id => {
                        switch (token.tag) {
                            .string_literal => condition.value = self.toker.getTokenSlice(token),
                            else => return printError("Error: Expected string", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
                        }
                    },
                    .bool => {
                        switch (token.tag) {
                            .bool_literal_true, .bool_literal_false => condition.value = self.toker.getTokenSlice(token),
                            else => return printError("Error: Expected bool", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
                        }
                    },
                    .int_array => {
                        const start_index = token.loc.start;
                        token = self.toker.next();
                        while (token.tag != Token.Tag.r_bracket) : (token = self.toker.next()) {
                            switch (token.tag) {
                                .int_literal => continue,
                                else => return printError("Error: Expected int or ].", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
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
                                else => return printError("Error: Expected float or ].", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
                            }
                        }
                        condition.value = self.toker.buffer[start_index..token.loc.end];
                    },
                    .str_array, .id_array => {
                        const start_index = token.loc.start;
                        token = self.toker.next();
                        while (token.tag != Token.Tag.r_bracket) : (token = self.toker.next()) {
                            switch (token.tag) {
                                .string_literal => continue,
                                else => return printError("Error: Expected string or ].", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
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
                                else => return printError("Error: Expected bool or ].", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
                            }
                        }
                        condition.value = self.toker.buffer[start_index..token.loc.end];
                    },
                }
                self.state = .end;
            },

            else => unreachable,
        };

        // Check if the condition is valid
        // TODO: Mqke q function outside the Parser
        switch (condition.operation) {
            .equal => switch (condition.data_type) {
                .int, .float, .str, .bool, .id => {},
                else => return printError("Error: Only int, float, str, bool can be compare with =.", ZiQlParserError.ConditionError, self.toker.buffer, token.loc.start, token.loc.end),
            },

            .different => switch (condition.data_type) {
                .int, .float, .str, .bool, .id => {},
                else => return printError("Error: Only int, float, str, bool can be compare with !=.", ZiQlParserError.ConditionError, self.toker.buffer, token.loc.start, token.loc.end),
            },

            .superior_or_equal => switch (condition.data_type) {
                .int, .float => {},
                else => return printError("Error: Only int, float can be compare with <=.", ZiQlParserError.ConditionError, self.toker.buffer, token.loc.start, token.loc.end),
            },

            .superior => switch (condition.data_type) {
                .int, .float => {},
                else => return printError("Error: Only int, float can be compare with <.", ZiQlParserError.ConditionError, self.toker.buffer, token.loc.start, token.loc.end),
            },

            .inferior_or_equal => switch (condition.data_type) {
                .int, .float => {},
                else => return printError("Error: Only int, float can be compare with >=.", ZiQlParserError.ConditionError, self.toker.buffer, token.loc.start, token.loc.end),
            },

            .inferior => switch (condition.data_type) {
                .int, .float => {},
                else => return printError("Error: Only int, float can be compare with >.", ZiQlParserError.ConditionError, self.toker.buffer, token.loc.start, token.loc.end),
            },

            // TODO:  Do it for IN and other stuff to
            else => unreachable,
        }

        return token;
    }

    /// When this function is call, next token should be [
    /// Check if an int is here -> check if ; is here -> check if member is here -> check if [ is here -> loop
    fn parseAdditionalData(self: *Parser, additional_data: *AdditionalData) !void {
        var token = self.toker.next();
        var keep_next = false;
        self.state = .expect_count_of_entity_to_find;

        while (self.state != .end) : ({
            token = if ((!keep_next) and (self.state != .end)) self.toker.next() else token;
            keep_next = false;
        }) switch (self.state) {
            .expect_count_of_entity_to_find => switch (token.tag) {
                .int_literal => {
                    const count = std.fmt.parseInt(usize, self.toker.getTokenSlice(token), 10) catch {
                        return printError("Error while transforming this into a integer.", ZiQlParserError.ParsingValueError, self.toker.buffer, token.loc.start, token.loc.end);
                    };
                    additional_data.entity_count_to_find = count;
                    self.state = .expect_semicolon_OR_right_bracket;
                },
                else => {
                    self.state = .expect_member;
                    keep_next = true;
                },
            },

            .expect_semicolon_OR_right_bracket => switch (token.tag) {
                .semicolon => self.state = .expect_member,
                .r_bracket => self.state = .end,
                else => return printError("Error: Expect ';' or ']'.", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
            },

            .expect_member => switch (token.tag) {
                .identifier => {
                    if (!self.file_engine.isMemberNameInStruct(self.struct_name, self.toker.getTokenSlice(token))) return printError("Member not found in struct.", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end);
                    try additional_data.member_to_find.append(
                        AdditionalDataMember.init(
                            self.allocator,
                            self.toker.getTokenSlice(token),
                        ),
                    );

                    self.state = .expect_comma_OR_r_bracket_OR_l_bracket;
                },
                else => return printError("Error: Expected a member name.", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
            },

            .expect_comma_OR_r_bracket_OR_l_bracket => switch (token.tag) {
                .comma => self.state = .expect_member,
                .r_bracket => self.state = .end,
                .l_bracket => {
                    try self.parseAdditionalData(
                        &additional_data.member_to_find.items[additional_data.member_to_find.items.len - 1].additional_data,
                    );
                    self.state = .expect_comma_OR_r_bracket;
                },
                else => return printError("Error: Expected , or ] or [", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
            },

            .expect_comma_OR_r_bracket => switch (token.tag) {
                .comma => self.state = .expect_member,
                .r_bracket => self.state = .end,
                else => return printError("Error: Expected , or ]", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
            },

            else => unreachable,
        };
    }

    /// Take the tokenizer and return a map of the ADD action.
    /// Keys are the member name and value are the string of the value in the query. E.g. 'Adrien' or '10'
    /// Entry token need to be (
    fn parseNewData(self: *Parser, member_map: *std.StringHashMap([]const u8)) !void {
        var token = self.toker.next();
        var keep_next = false;
        var member_name: []const u8 = undefined; // Maybe use allocator.alloc
        self.state = .expect_member;

        while (self.state != .end) : ({
            token = if (!keep_next) self.toker.next() else token;
            keep_next = false;
        }) switch (self.state) {
            .expect_member => switch (token.tag) {
                .identifier => {
                    member_name = self.toker.getTokenSlice(token);
                    if (!self.file_engine.isMemberNameInStruct(self.struct_name, member_name)) return printError("Member not found in struct.", ZiQlParserError.MemberNotFound, self.toker.buffer, token.loc.start, token.loc.end);
                    self.state = .expect_equal;
                },
                else => return printError("Error: Expected member name.", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
            },

            .expect_equal => switch (token.tag) {
                // TODO: Implement stuff to manipulate array like APPEND or REMOVE
                .equal => self.state = .expect_new_value,
                else => return printError("Error: Expected =", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
            },

            .expect_new_value => {
                const data_type = self.file_engine.memberName2DataType(self.struct_name, member_name);
                switch (data_type.?) {
                    .int => switch (token.tag) {
                        .int_literal, .keyword_null => {
                            member_map.put(member_name, self.toker.getTokenSlice(token)) catch @panic("Could not add member name and value to map in getMapOfMember");
                            self.state = .expect_comma_OR_end;
                        },
                        else => return printError("Error: Expected int", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
                    },
                    .float => switch (token.tag) {
                        .float_literal, .keyword_null => {
                            member_map.put(member_name, self.toker.getTokenSlice(token)) catch @panic("Could not add member name and value to map in getMapOfMember");
                            self.state = .expect_comma_OR_end;
                        },
                        else => return printError("Error: Expected float", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
                    },
                    .bool => switch (token.tag) {
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
                        else => return printError("Error: Expected bool: true false", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
                    },
                    .str, .id => switch (token.tag) {
                        .string_literal, .keyword_null => {
                            member_map.put(member_name, self.toker.getTokenSlice(token)) catch @panic("Could not add member name and value to map in getMapOfMember");
                            self.state = .expect_comma_OR_end;
                        },
                        else => return printError("Error: Expected string between ''", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
                    },
                    // TODO: Maybe upgrade that to use multiple state
                    .int_array => switch (token.tag) {
                        .l_bracket => {
                            const start_index = token.loc.start;
                            token = self.toker.next();
                            while (token.tag != .r_bracket) : (token = self.toker.next()) {
                                switch (token.tag) {
                                    .int_literal => continue,
                                    else => return printError("Error: Expected int or ].", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
                                }
                            }
                            // Maybe change that as it just recreate a string that is already in the buffer
                            member_map.put(member_name, self.toker.buffer[start_index..token.loc.end]) catch @panic("Couln't add string of array in data map");
                            self.state = .expect_comma_OR_end;
                        },
                        else => return printError("Error: Expected [ to start an array", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
                    },
                    .float_array => switch (token.tag) {
                        .l_bracket => {
                            const start_index = token.loc.start;
                            token = self.toker.next();
                            while (token.tag != .r_bracket) : (token = self.toker.next()) {
                                switch (token.tag) {
                                    .float_literal => continue,
                                    else => return printError("Error: Expected float or ].", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
                                }
                            }
                            // Maybe change that as it just recreate a string that is already in the buffer
                            member_map.put(member_name, self.toker.buffer[start_index..token.loc.end]) catch @panic("Couln't add string of array in data map");
                            self.state = .expect_comma_OR_end;
                        },
                        else => return printError("Error: Expected [ to start an array", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
                    },
                    .bool_array => switch (token.tag) {
                        .l_bracket => {
                            const start_index = token.loc.start;
                            token = self.toker.next();
                            while (token.tag != .r_bracket) : (token = self.toker.next()) {
                                switch (token.tag) {
                                    .bool_literal_false, .bool_literal_true => continue,
                                    else => return printError("Error: Expected bool or ].", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
                                }
                            }
                            // Maybe change that as it just recreate a string that is already in the buffer
                            member_map.put(member_name, self.toker.buffer[start_index..token.loc.end]) catch @panic("Couln't add string of array in data map");
                            self.state = .expect_comma_OR_end;
                        },
                        else => return printError("Error: Expected [ to start an array", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
                    },
                    .str_array, .id_array => switch (token.tag) {
                        .l_bracket => {
                            const start_index = token.loc.start;
                            token = self.toker.next();
                            while (token.tag != .r_bracket) : (token = self.toker.next()) {
                                switch (token.tag) {
                                    .string_literal => continue,
                                    else => return printError("Error: Expected str or ].", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
                                }
                            }
                            // Maybe change that as it just recreate a string that is already in the buffer
                            member_map.put(member_name, self.toker.buffer[start_index..token.loc.end]) catch @panic("Couln't add string of array in data map");
                            self.state = .expect_comma_OR_end;
                        },
                        else => return printError("Error: Expected [ to start an array", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
                    },
                }
            },

            .expect_comma_OR_end => {
                switch (token.tag) {
                    .r_paren => self.state = .end,
                    .comma => self.state = .expect_member,
                    else => return printError("Error: Expect , or )", ZiQlParserError.SynthaxError, self.toker.buffer, token.loc.start, token.loc.end),
                }
            },

            else => unreachable,
        };
    }
};

test "ADD" {
    try testParsing("ADD User (name = 'Bob', email='bob@email.com', age=55, scores=[ 1 ], friends=[])");
    try testParsing("ADD User (name = 'Bob', email='bob@email.com', age=55, scores=[ 1 ], friends=[])");
    try testParsing("ADD User (name = 'Bob', email='bob@email.com', age=55, scores=[ 1 ], friends=[])");
}

test "UPDATE" {
    try testParsing("UPDATE User {name = 'Bob'} TO (email='new@gmail.com')");
}

test "DELETE" {
    try testParsing("DELETE User {name='Bob'}");
}

test "GRAB filter with string" {
    try testParsing("GRAB User {name = 'Bob'}");
    try testParsing("GRAB User {name != 'Brittany Rogers'}");
}

test "GRAB with additional data" {
    try testParsing("GRAB User [1] {age < 18}");
    try testParsing("GRAB User [name] {age < 18}");
    try testParsing("GRAB User [100; name] {age < 18}");
}

test "GRAB filter with int" {
    try testParsing("GRAB User {age = 18}");
    try testParsing("GRAB User {age > 18}");
    try testParsing("GRAB User {age < 18}");
    try testParsing("GRAB User {age <= 18}");
    try testParsing("GRAB User {age >= 18}");
    try testParsing("GRAB User {age != 18}");
}

test "Specific query" {
    try testParsing("GRAB User");
    try testParsing("GRAB User {}");
    try testParsing("GRAB User [1]");
}

test "Synthax error" {
    try expectParsingError("GRAB {}", ZiQlParserError.StructNotFound);
    try expectParsingError("GRAB User {qwe = 'qwe'}", ZiQlParserError.MemberNotFound);
    try expectParsingError("ADD User (name='Bob')", ZiQlParserError.MemberMissing);
    try expectParsingError("GRAB User {name='Bob'", ZiQlParserError.SynthaxError);
    try expectParsingError("GRAB User {age = 50 name='Bob'}", ZiQlParserError.SynthaxError);
    try expectParsingError("GRAB User {age <14 AND (age>55}", ZiQlParserError.SynthaxError);
    try expectParsingError("GRAB User {name < 'Hello'}", ZiQlParserError.ConditionError);
}

fn testParsing(source: [:0]const u8) !void {
    const allocator = std.testing.allocator;

    const path = try allocator.dupe(u8, "ZipponDB");
    var file_engine = FileEngine.init(allocator, path);
    defer file_engine.deinit();

    var tokenizer = Tokenizer.init(source);
    var parser = Parser.init(allocator, &tokenizer, &file_engine);
    defer parser.deinit();

    try parser.parse();
}

fn expectParsingError(source: [:0]const u8, err: ZiQlParserError) !void {
    const allocator = std.testing.allocator;

    const path = try allocator.dupe(u8, "ZipponDB");
    var file_engine = FileEngine.init(allocator, path);
    defer file_engine.deinit();

    var tokenizer = Tokenizer.init(source);
    var parser = Parser.init(allocator, &tokenizer, &file_engine);
    defer parser.deinit();

    try std.testing.expectError(err, parser.parse());
}
