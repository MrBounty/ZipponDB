const std = @import("std");
const Allocator = std.mem.Allocator;
const FileEngine = @import("fileEngine.zig").FileEngine;
const Condition = @import("fileEngine.zig").FileEngine.Condition;
const Tokenizer = @import("tokenizers/ziql.zig").Tokenizer;
const Token = @import("tokenizers/ziql.zig").Token;
const UUID = @import("types/uuid.zig").UUID;
const AND = @import("types/uuid.zig").AND;
const OR = @import("types/uuid.zig").OR;
const DataType = @import("types/dataType.zig").DataType;
const AdditionalData = @import("stuffs/additionalData.zig").AdditionalData;
const AdditionalDataMember = @import("stuffs/additionalData.zig").AdditionalDataMember;
const send = @import("stuffs/utils.zig").send;
const printError = @import("stuffs/utils.zig").printError;

const ZiQlParserError = @import("stuffs/errors.zig").ZiQlParserError;
const ZipponError = @import("stuffs/errors.zig").ZipponError;

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
    toker: *Tokenizer,
    file_engine: *FileEngine,

    pub fn init(allocator: Allocator, toker: *Tokenizer, file_engine: *FileEngine) Parser {
        // Do I need to init a FileEngine at each Parser, can't I put it in the CLI parser instead ?
        return Parser{
            .allocator = allocator,
            .toker = toker,
            .file_engine = file_engine,
        };
    }

    // TODO: Update to use ASC and DESC
    // Maybe create a Sender struct or something like that
    fn sendEntity(self: Parser, uuid_list: *std.ArrayList(UUID), additional_data: AdditionalData, struct_name: []const u8) void {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        // Pop some element if the array is too long
        if ((additional_data.entity_count_to_find != 0) and (additional_data.entity_count_to_find < uuid_list.items.len)) {
            const to_pop = uuid_list.items.len - additional_data.entity_count_to_find;
            for (0..to_pop) |_| _ = uuid_list.pop();
        }

        // Im gonna need a function in the file engine to parse and write in the buffer
        self.file_engine.parseAndWriteToSend(struct_name, uuid_list.items, &buffer, additional_data) catch @panic("Error parsing data to send");

        send("{s}", .{buffer.items});
    }

    /// Format a list of UUID into a json and send it
    pub fn sendUUIDs(self: Parser, uuid_list: []UUID) ZiQlParserError!void {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        const writer = buffer.writer();
        writer.writeByte('[') catch return ZiQlParserError.WriteError;
        for (uuid_list) |uuid| {
            writer.writeByte('"') catch return ZiQlParserError.WriteError;
            writer.writeAll(&uuid.format_uuid()) catch return ZiQlParserError.WriteError;
            writer.writeAll("\", ") catch return ZiQlParserError.WriteError;
        }
        writer.writeByte(']') catch return ZiQlParserError.WriteError;

        send("{s}", .{buffer.items});
    }

    pub fn parse(self: Parser) ZipponError!void {
        var state: State = .start;
        var additional_data = AdditionalData.init(self.allocator);
        defer additional_data.deinit();
        var struct_name: []const u8 = undefined;
        var action: enum { GRAB, ADD, UPDATE, DELETE } = undefined;

        var token = self.toker.next();
        var keep_next = false; // Use in the loop to prevent to get the next token when continue. Just need to make it true and it is reset at every loop

        while (state != State.end) : ({
            token = if (!keep_next) self.toker.next() else token;
            keep_next = false;
        }) switch (state) {
            .start => switch (token.tag) {
                .keyword_grab => {
                    action = .GRAB;
                    state = .expect_struct_name;
                },
                .keyword_add => {
                    action = .ADD;
                    state = .expect_struct_name;
                },
                .keyword_update => {
                    action = .UPDATE;
                    state = .expect_struct_name;
                },
                .keyword_delete => {
                    action = .DELETE;
                    state = .expect_struct_name;
                },
                else => return printError(
                    "Error: Expected action keyword. Available: GRAB ADD DELETE UPDATE",
                    ZiQlParserError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },

            .expect_struct_name => {
                // Check if the struct name is in the schema
                struct_name = self.toker.getTokenSlice(token);
                if (token.tag != .identifier) return printError(
                    "Error: Missing struct name",
                    ZiQlParserError.StructNotFound,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                );
                if (!self.file_engine.isStructNameExists(struct_name)) return printError(
                    "Error: struct name not found in schema.",
                    ZiQlParserError.StructNotFound,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                );
                switch (action) {
                    .ADD => state = .expect_new_data,
                    else => state = .expect_filter_or_additional_data,
                }
            },

            .expect_filter_or_additional_data => {
                keep_next = true;
                switch (token.tag) {
                    .l_bracket => state = .parse_additional_data,
                    .l_brace => state = switch (action) {
                        .GRAB => .filter_and_send,
                        .UPDATE => .filter_and_update,
                        .DELETE => .filter_and_delete,
                        else => unreachable,
                    },
                    .eof => state = .filter_and_send,
                    else => return printError(
                        "Error: Expect [ for additional data or { for a filter",
                        ZiQlParserError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    ),
                }
            },

            .parse_additional_data => {
                try self.parseAdditionalData(&additional_data, struct_name);
                state = switch (action) {
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
                    _ = try self.parseFilter(&array, struct_name, true);

                    self.sendEntity(&array, additional_data, struct_name);
                    state = .end;
                },
                .eof => {
                    var array = std.ArrayList(UUID).init(self.allocator);
                    defer array.deinit();
                    try self.file_engine.getAllUUIDList(struct_name, &array);

                    self.sendEntity(&array, additional_data, struct_name);
                    state = .end;
                },
                else => return printError(
                    "Error: Expected filter.",
                    ZiQlParserError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },

            // TODO: Optimize so it doesnt use parseFilter but just parse the file and directly check the condition. Here I end up parsing 2 times.
            .filter_and_update => switch (token.tag) {
                .l_brace => {
                    var uuids = std.ArrayList(UUID).init(self.allocator);
                    defer uuids.deinit();
                    token = try self.parseFilter(&uuids, struct_name, true);

                    if (token.tag != .keyword_to) return printError(
                        "Error: Expected TO",
                        ZiQlParserError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );

                    token = self.toker.next();
                    if (token.tag != .l_paren) return printError(
                        "Error: Expected (",
                        ZiQlParserError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );

                    var data_map = std.StringHashMap([]const u8).init(self.allocator);
                    defer data_map.deinit();
                    try self.parseNewData(&data_map, struct_name);

                    try self.file_engine.updateEntities(struct_name, uuids.items, data_map);
                    try self.sendUUIDs(uuids.items);
                    state = .end;
                },
                .keyword_to => {
                    var array = std.ArrayList(UUID).init(self.allocator);
                    defer array.deinit();
                    try self.file_engine.getAllUUIDList(struct_name, &array);

                    token = self.toker.next();
                    if (token.tag != .l_paren) return printError(
                        "Error: Expected (",
                        ZiQlParserError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );

                    var data_map = std.StringHashMap([]const u8).init(self.allocator);
                    defer data_map.deinit();
                    try self.parseNewData(&data_map, struct_name);

                    try self.file_engine.updateEntities(struct_name, array.items, data_map);
                    state = .end;
                },
                else => return printError(
                    "Error: Expected filter or TO.",
                    ZiQlParserError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },

            .filter_and_delete => switch (token.tag) {
                .l_brace => {
                    var uuids = std.ArrayList(UUID).init(self.allocator);
                    defer uuids.deinit();
                    _ = try self.parseFilter(&uuids, struct_name, true);
                    _ = try self.file_engine.deleteEntities(struct_name, uuids.items);
                    try self.sendUUIDs(uuids.items);
                    state = .end;
                },
                .eof => {
                    var uuids = std.ArrayList(UUID).init(self.allocator);
                    defer uuids.deinit();
                    try self.file_engine.getAllUUIDList(struct_name, &uuids);
                    _ = try self.file_engine.deleteEntities(struct_name, uuids.items);
                    try self.sendUUIDs(uuids.items);
                    state = .end;
                },
                else => return printError(
                    "Error: Expected filter.",
                    ZiQlParserError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },

            .expect_new_data => switch (token.tag) {
                .l_paren => {
                    keep_next = true;
                    state = .parse_new_data_and_add_data;
                },
                else => return printError(
                    "Error: Expected new data starting with (",
                    ZiQlParserError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },

            .parse_new_data_and_add_data => {
                var data_map = std.StringHashMap([]const u8).init(self.allocator);
                defer data_map.deinit();
                try self.parseNewData(&data_map, struct_name);

                var error_message_buffer = std.ArrayList(u8).init(self.allocator);
                defer error_message_buffer.deinit();
                const error_message_buffer_writer = error_message_buffer.writer();
                error_message_buffer_writer.writeAll("Error missing: ") catch return ZipponError.WriteError;

                // TODO: Print the entire list of missing
                if (!(self.file_engine.checkIfAllMemberInMap(struct_name, &data_map, &error_message_buffer) catch {
                    return ZiQlParserError.StructNotFound;
                })) {
                    _ = error_message_buffer.pop();
                    _ = error_message_buffer.pop();
                    return printError(
                        error_message_buffer.items,
                        ZiQlParserError.MemberMissing,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );
                }
                const uuid = self.file_engine.writeEntity(struct_name, data_map) catch {
                    send("ZipponDB error: Couln't write new data to file", .{});
                    continue;
                };

                var buffer = std.ArrayList(u8).init(self.allocator);
                defer buffer.deinit();

                const writer = buffer.writer();
                writer.writeByte('[') catch return ZiQlParserError.WriteError;
                writer.writeByte('"') catch return ZiQlParserError.WriteError;
                writer.writeAll(&uuid.format_uuid()) catch return ZiQlParserError.WriteError;
                writer.writeAll("\"") catch return ZiQlParserError.WriteError;
                writer.writeByte(']') catch return ZiQlParserError.WriteError;
                send("{s}", .{buffer.items});

                state = .end;
            },

            else => unreachable,
        };
    }

    /// Take an array of UUID and populate it with what match what is between {}
    /// Main is to know if between {} or (), main is true if between {}, otherwise between () inside {}
    /// TODO: Optimize this so it can use multiple condition at the same time instead of parsing the all file for each condition
    fn parseFilter(self: Parser, left_array: *std.ArrayList(UUID), struct_name: []const u8, main: bool) ZipponError!Token {
        var token = self.toker.next();
        var keep_next = false;
        var state: State = .expect_left_condition;

        var left_condition = Condition.init(struct_name);
        var curent_operation: enum { and_, or_ } = undefined;

        while (state != .end) : ({
            token = if (!keep_next) self.toker.next() else token;
            keep_next = false;
        }) switch (state) {
            .expect_left_condition => switch (token.tag) {
                .r_brace => {
                    try self.file_engine.getAllUUIDList(struct_name, left_array);
                    state = .end;
                },
                else => {
                    token = try self.parseCondition(&left_condition, &token);
                    try self.file_engine.getUUIDListUsingCondition(left_condition, left_array);
                    state = .expect_ANDOR_OR_end;
                    keep_next = true;
                },
            },

            .expect_ANDOR_OR_end => switch (token.tag) {
                .r_brace => if (main) {
                    state = .end;
                } else {
                    return printError(
                        "Error: Expected } to end main condition or AND/OR to continue it",
                        ZiQlParserError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );
                },
                .r_paren => if (!main) {
                    state = .end;
                } else {
                    return printError(
                        "Error: Expected ) to end inside condition or AND/OR to continue it",
                        ZiQlParserError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );
                },
                .keyword_and => {
                    curent_operation = .and_;
                    state = .expect_right_uuid_array;
                },
                .keyword_or => {
                    curent_operation = .or_;
                    state = .expect_right_uuid_array;
                },
                else => return printError(
                    "Error: Expected a condition including AND OR or the end of the filter with } or )",
                    ZiQlParserError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
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
                    },
                    else => return printError(
                        "Error: Expected ( or member name.",
                        ZiQlParserError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    ),
                }

                switch (curent_operation) {
                    .and_ => AND(left_array, &right_array) catch return ZipponError.AndOrError,
                    .or_ => OR(left_array, &right_array) catch return ZipponError.AndOrError,
                }
                state = .expect_ANDOR_OR_end;
            },

            else => unreachable,
        };

        return token;
    }

    /// Parse to get a Condition. Which is a struct that is use by the FileEngine to retreive data.
    /// In the query, it is this part name = 'Bob' or age <= 10
    fn parseCondition(self: Parser, condition: *Condition, token_ptr: *Token) ZipponError!Token {
        var keep_next = false;
        var state: State = .expect_member;
        var token = token_ptr.*;

        while (state != .end) : ({
            token = if (!keep_next) self.toker.next() else token;
            keep_next = false;
        }) switch (state) {
            .expect_member => switch (token.tag) {
                .identifier => {
                    if (!(self.file_engine.isMemberNameInStruct(condition.struct_name, self.toker.getTokenSlice(token)) catch {
                        return printError(
                            "Error: Struct not found.",
                            ZiQlParserError.StructNotFound,
                            self.toker.buffer,
                            token.loc.start,
                            token.loc.end,
                        );
                    })) {
                        return printError(
                            "Error: Member not part of struct.",
                            ZiQlParserError.MemberNotFound,
                            self.toker.buffer,
                            token.loc.start,
                            token.loc.end,
                        );
                    }
                    condition.data_type = self.file_engine.memberName2DataType(
                        condition.struct_name,
                        self.toker.getTokenSlice(token),
                    ) catch return ZiQlParserError.MemberNotFound;
                    condition.member_name = self.toker.getTokenSlice(token);
                    state = State.expect_operation;
                },
                else => return printError(
                    "Error: Expected member name.",
                    ZiQlParserError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },

            .expect_operation => {
                switch (token.tag) {
                    .equal => condition.operation = .equal, // =
                    .angle_bracket_left => condition.operation = .inferior, // <
                    .angle_bracket_right => condition.operation = .superior, // >
                    .angle_bracket_left_equal => condition.operation = .inferior_or_equal, // <=
                    .angle_bracket_right_equal => condition.operation = .superior_or_equal, // >=
                    .bang_equal => condition.operation = .different, // !=
                    else => return printError(
                        "Error: Expected condition. Including < > <= >= = !=",
                        ZiQlParserError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    ),
                }
                state = State.expect_value;
            },

            .expect_value => {
                const start_index = token.loc.start;
                const expected_tag: ?Token.Tag = switch (condition.data_type) {
                    .int => .int_literal,
                    .float => .float_literal,
                    .str => .string_literal,
                    .link => .uuid_literal,
                    .date => .date_literal,
                    .time => .time_literal,
                    .datetime => .datetime_literal,
                    .int_array => .int_literal,
                    .float_array => .float_literal,
                    .link_array => .uuid_literal,
                    .str_array => .string_literal,
                    .date_array => .date_literal,
                    .time_array => .time_literal,
                    .datetime_array => .datetime_literal,
                    .bool, .bool_array => null, // handle bool separately
                };

                if (expected_tag) |tag| {
                    if (condition.data_type.is_array()) {
                        token = try self.checkTokensInArray(tag);
                    } else {
                        if (token.tag != tag) {
                            return printError(
                                "Error: Wrong type", // TODO: Print the expected type
                                ZiQlParserError.SynthaxError,
                                self.toker.buffer,
                                token.loc.start,
                                token.loc.end,
                            );
                        }
                    }
                } else {
                    // handle bool and bool array separately
                    if (condition.data_type == .bool) {
                        if (token.tag != .bool_literal_true and token.tag != .bool_literal_false) {
                            return printError(
                                "Error: Expected bool",
                                ZiQlParserError.SynthaxError,
                                self.toker.buffer,
                                token.loc.start,
                                token.loc.end,
                            );
                        }
                    } else if (condition.data_type == .bool_array) {
                        token = self.toker.next();
                        while (token.tag != .r_bracket) : (token = self.toker.next()) {
                            if (token.tag != .bool_literal_true and token.tag != .bool_literal_false) {
                                return printError(
                                    "Error: Expected bool or ]",
                                    ZiQlParserError.SynthaxError,
                                    self.toker.buffer,
                                    token.loc.start,
                                    token.loc.end,
                                );
                            }
                        }
                    }
                }

                condition.value = self.toker.buffer[start_index..token.loc.end];
                state = .end;
            },

            else => unreachable,
        };

        // Check if the condition is valid
        switch (condition.operation) {
            .equal => switch (condition.data_type) {
                .int, .float, .str, .bool, .link, .date, .time, .datetime => {},
                else => return printError(
                    "Error: Only int, float, str, bool, date, time, datetime can be compare with =.",
                    ZiQlParserError.ConditionError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },

            .different => switch (condition.data_type) {
                .int, .float, .str, .bool, .link, .date, .time, .datetime => {},
                else => return printError(
                    "Error: Only int, float, str, bool, date, time, datetime can be compare with !=.",
                    ZiQlParserError.ConditionError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },

            .superior_or_equal => switch (condition.data_type) {
                .int, .float, .date, .time, .datetime => {},
                else => return printError(
                    "Error: Only int, float, date, time, datetime can be compare with >=.",
                    ZiQlParserError.ConditionError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },

            .superior => switch (condition.data_type) {
                .int, .float, .date, .time, .datetime => {},
                else => return printError(
                    "Error: Only int, float, date, time, datetime can be compare with >.",
                    ZiQlParserError.ConditionError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },

            .inferior_or_equal => switch (condition.data_type) {
                .int, .float, .date, .time, .datetime => {},
                else => return printError(
                    "Error: Only int, float, date, time, datetime can be compare with <=.",
                    ZiQlParserError.ConditionError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },

            .inferior => switch (condition.data_type) {
                .int, .float, .date, .time, .datetime => {},
                else => return printError(
                    "Error: Only int, float, date, time, datetime can be compare with <.",
                    ZiQlParserError.ConditionError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },

            else => unreachable,
        }

        return token;
    }

    /// When this function is call, next token should be [
    /// Check if an int is here -> check if ; is here -> check if member is here -> check if [ is here -> loop
    fn parseAdditionalData(self: Parser, additional_data: *AdditionalData, struct_name: []const u8) ZipponError!void {
        var token = self.toker.next();
        var keep_next = false;
        var state: State = .expect_count_of_entity_to_find;

        while (state != .end) : ({
            token = if ((!keep_next) and (state != .end)) self.toker.next() else token;
            keep_next = false;
        }) switch (state) {
            .expect_count_of_entity_to_find => switch (token.tag) {
                .int_literal => {
                    const count = std.fmt.parseInt(usize, self.toker.getTokenSlice(token), 10) catch {
                        return printError(
                            "Error while transforming this into a integer.",
                            ZiQlParserError.ParsingValueError,
                            self.toker.buffer,
                            token.loc.start,
                            token.loc.end,
                        );
                    };
                    additional_data.entity_count_to_find = count;
                    state = .expect_semicolon_OR_right_bracket;
                },
                else => {
                    state = .expect_member;
                    keep_next = true;
                },
            },

            .expect_semicolon_OR_right_bracket => switch (token.tag) {
                .semicolon => state = .expect_member,
                .r_bracket => state = .end,
                else => return printError(
                    "Error: Expect ';' or ']'.",
                    ZiQlParserError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },

            .expect_member => switch (token.tag) {
                .identifier => {
                    if (!(self.file_engine.isMemberNameInStruct(struct_name, self.toker.getTokenSlice(token)) catch {
                        return printError(
                            "Struct not found.",
                            ZiQlParserError.StructNotFound,
                            self.toker.buffer,
                            token.loc.start,
                            token.loc.end,
                        );
                    })) {
                        return printError(
                            "Member not found in struct.",
                            ZiQlParserError.MemberNotFound,
                            self.toker.buffer,
                            token.loc.start,
                            token.loc.end,
                        );
                    }
                    additional_data.member_to_find.append(
                        AdditionalDataMember.init(
                            self.allocator,
                            self.toker.getTokenSlice(token),
                        ),
                    ) catch return ZipponError.MemoryError;

                    state = .expect_comma_OR_r_bracket_OR_l_bracket;
                },
                else => return printError(
                    "Error: Expected a member name.",
                    ZiQlParserError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },

            .expect_comma_OR_r_bracket_OR_l_bracket => switch (token.tag) {
                .comma => state = .expect_member,
                .r_bracket => state = .end,
                .l_bracket => {
                    try self.parseAdditionalData(
                        &additional_data.member_to_find.items[additional_data.member_to_find.items.len - 1].additional_data,
                        struct_name,
                    );
                    state = .expect_comma_OR_r_bracket;
                },
                else => return printError(
                    "Error: Expected , or ] or [",
                    ZiQlParserError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },

            .expect_comma_OR_r_bracket => switch (token.tag) {
                .comma => state = .expect_member,
                .r_bracket => state = .end,
                else => return printError(
                    "Error: Expected , or ]",
                    ZiQlParserError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },

            else => unreachable,
        };
    }

    /// Take the tokenizer and return a map of the ADD action.
    /// Keys are the member name and value are the string of the value in the query. E.g. 'Adrien' or '10'
    /// Entry token need to be (
    fn parseNewData(self: Parser, member_map: *std.StringHashMap([]const u8), struct_name: []const u8) !void {
        var token = self.toker.next();
        var keep_next = false;
        var member_name: []const u8 = undefined; // Maybe use allocator.alloc
        var state: State = .expect_member;

        while (state != .end) : ({
            token = if (!keep_next) self.toker.next() else token;
            keep_next = false;
        }) switch (state) {
            .expect_member => switch (token.tag) {
                .identifier => {
                    member_name = self.toker.getTokenSlice(token);
                    if (!(self.file_engine.isMemberNameInStruct(struct_name, member_name) catch {
                        return ZiQlParserError.StructNotFound;
                    })) return printError(
                        "Member not found in struct.",
                        ZiQlParserError.MemberNotFound,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );
                    state = .expect_equal;
                },
                else => return printError(
                    "Error: Expected member name.",
                    ZiQlParserError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },

            .expect_equal => switch (token.tag) {
                // TODO: Implement stuff to manipulate array like APPEND or REMOVE
                .equal => state = .expect_new_value,
                else => return printError(
                    "Error: Expected =",
                    ZiQlParserError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },

            .expect_new_value => {
                const data_type = self.file_engine.memberName2DataType(struct_name, member_name) catch return ZiQlParserError.StructNotFound;
                const start_index = token.loc.start;

                const expected_tag: ?Token.Tag = switch (data_type) {
                    .int => .int_literal,
                    .float => .float_literal,
                    .str => .string_literal,
                    .link => .uuid_literal,
                    .date => .date_literal,
                    .time => .time_literal,
                    .datetime => .datetime_literal,
                    .int_array => .int_literal,
                    .float_array => .float_literal,
                    .link_array => .uuid_literal,
                    .str_array => .string_literal,
                    .date_array => .date_literal,
                    .time_array => .time_literal,
                    .datetime_array => .datetime_literal,
                    // Handle bool and arrays separately
                    .bool, .bool_array => null,
                };

                if (expected_tag) |tag| {
                    if (data_type.is_array()) {
                        if (token.tag != .l_bracket) {
                            return printError(
                                "Error: Expected [ to start an array",
                                ZiQlParserError.SynthaxError,
                                self.toker.buffer,
                                token.loc.start,
                                token.loc.end,
                            );
                        }
                        token = try self.checkTokensInArray(tag);
                    } else {
                        if (token.tag != tag and token.tag != .keyword_null) {
                            return printError(
                                "Error: Expected {s}",
                                ZiQlParserError.SynthaxError,
                                self.toker.buffer,
                                token.loc.start,
                                token.loc.end,
                            );
                        }
                    }

                    member_map.put(member_name, self.toker.buffer[start_index..token.loc.end]) catch return ZipponError.MemoryError;
                } else {
                    // Handle bool and bool array
                    switch (data_type) {
                        .bool => {
                            switch (token.tag) {
                                .bool_literal_true => {
                                    member_map.put(member_name, "1") catch @panic("Could not add member name and value to map in getMapOfMember");
                                },
                                .bool_literal_false => {
                                    member_map.put(member_name, "0") catch @panic("Could not add member name and value to map in getMapOfMember");
                                },
                                .keyword_null => {
                                    member_map.put(member_name, self.toker.getTokenSlice(token)) catch return ZipponError.MemoryError;
                                },
                                else => return printError(
                                    "Error: Expected bool: true, false, or null",
                                    ZiQlParserError.SynthaxError,
                                    self.toker.buffer,
                                    token.loc.start,
                                    token.loc.end,
                                ),
                            }
                        },
                        .bool_array => {
                            if (token.tag != .l_bracket) {
                                return printError(
                                    "Error: Expected [ to start an array",
                                    ZiQlParserError.SynthaxError,
                                    self.toker.buffer,
                                    token.loc.start,
                                    token.loc.end,
                                );
                            }
                            token = self.toker.next();
                            while (token.tag != .r_bracket) : (token = self.toker.next()) {
                                if (token.tag != .bool_literal_true and token.tag != .bool_literal_false) {
                                    return printError(
                                        "Error: Expected bool or ]",
                                        ZiQlParserError.SynthaxError,
                                        self.toker.buffer,
                                        token.loc.start,
                                        token.loc.end,
                                    );
                                }
                            }
                            member_map.put(member_name, self.toker.buffer[start_index..token.loc.end]) catch return ZipponError.MemoryError;
                        },
                        else => unreachable,
                    }
                }

                state = .expect_comma_OR_end;
            },

            .expect_comma_OR_end => {
                switch (token.tag) {
                    .r_paren => state = .end,
                    .comma => state = .expect_member,
                    else => return printError(
                        "Error: Expect , or )",
                        ZiQlParserError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    ),
                }
            },

            else => unreachable,
        };
    }

    // Utils

    /// Check if all token in an array is of one specific type
    fn checkTokensInArray(self: Parser, tag: Token.Tag) ZipponError!Token {
        var token = self.toker.next();
        while (token.tag != .r_bracket) : (token = self.toker.next()) {
            if (token.tag != tag) return printError(
                "Error: Wrong type.",
                ZiQlParserError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            );
        }
        return token;
    }
};

test "ADD" {
    try testParsing("ADD User (name = 'Bob', email='bob@email.com', age=55, scores=[ 1 ], friends=[], bday=2000/01/01, a_time=12:04, last_order=2000/01/01-12:45)");
    try testParsing("ADD User (name = 'Bob', email='bob@email.com', age=55, scores=[ 1 ], friends=[], bday=2000/01/01, a_time=12:04:54, last_order=2000/01/01-12:45)");
    try testParsing("ADD User (name = 'Bob', email='bob@email.com', age=-55, scores=[ 1 ], friends=[], bday=2000/01/01, a_time=12:04:54.8741, last_order=2000/01/01-12:45)");
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
    try testParsing("GRAB User {age > -18}");
    try testParsing("GRAB User {age < 18}");
    try testParsing("GRAB User {age <= 18}");
    try testParsing("GRAB User {age >= 18}");
    try testParsing("GRAB User {age != 18}");
}

test "GRAB filter with date" {
    try testParsing("GRAB User {bday > 2000/01/01}");
    try testParsing("GRAB User {a_time < 08:00}");
    try testParsing("GRAB User {last_order > 2000/01/01-12:45}");
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
    const TEST_DATA_DIR = @import("config.zig").TEST_DATA_DIR;
    const allocator = std.testing.allocator;

    const path = try allocator.dupe(u8, TEST_DATA_DIR);
    var file_engine = FileEngine.init(allocator, path);
    defer file_engine.deinit();

    var tokenizer = Tokenizer.init(source);
    var parser = Parser.init(allocator, &tokenizer, &file_engine);

    try parser.parse();
}

fn expectParsingError(source: [:0]const u8, err: ZiQlParserError) !void {
    const TEST_DATA_DIR = @import("config.zig").TEST_DATA_DIR;
    const allocator = std.testing.allocator;

    const path = try allocator.dupe(u8, TEST_DATA_DIR);
    var file_engine = FileEngine.init(allocator, path);
    defer file_engine.deinit();

    var tokenizer = Tokenizer.init(source);
    var parser = Parser.init(allocator, &tokenizer, &file_engine);

    try std.testing.expectError(err, parser.parse());
}
