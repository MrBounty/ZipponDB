const std = @import("std");
const Allocator = std.mem.Allocator;
const FileEngine = @import("fileEngine.zig").FileEngine;
const SchemaEngine = @import("schemaEngine.zig").SchemaEngine;
const Tokenizer = @import("tokenizers/ziql.zig").Tokenizer;
const Token = @import("tokenizers/ziql.zig").Token;

const dtype = @import("dtype");
const UUID = dtype.UUID;

const Filter = @import("stuffs/filter.zig").Filter;
const Condition = @import("stuffs/filter.zig").Condition;
const ConditionValue = @import("stuffs/filter.zig").ConditionValue;
const ComparisonOperator = @import("stuffs/filter.zig").ComparisonOperator;

const AdditionalData = @import("stuffs/additionalData.zig").AdditionalData;
const AdditionalDataMember = @import("stuffs/additionalData.zig").AdditionalDataMember;
const send = @import("stuffs/utils.zig").send;
const printError = @import("stuffs/utils.zig").printError;

const ZiQlParserError = @import("stuffs/errors.zig").ZiQlParserError;
const ZipponError = @import("stuffs/errors.zig").ZipponError;

const PRINT_STATE = @import("config.zig").PRINT_STATE;

const log = std.log.scoped(.ziqlParser);

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
    expect_condition,
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
    toker: *Tokenizer,
    file_engine: *FileEngine,
    schema_engine: *SchemaEngine,

    // TODO: Improve memory management, stop using an alloc in init maybe
    pub fn init(toker: *Tokenizer, file_engine: *FileEngine, schema_engine: *SchemaEngine) Parser {
        // Do I need to init a FileEngine at each Parser, can't I put it in the CLI parser instead ?
        return Parser{
            .toker = toker,
            .file_engine = file_engine,
            .schema_engine = schema_engine,
        };
    }

    pub fn parse(self: Parser) ZipponError!void {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        var state: State = .start;
        var additional_data = AdditionalData.init(allocator);
        defer additional_data.deinit();
        var struct_name: []const u8 = undefined;
        var action: enum { GRAB, ADD, UPDATE, DELETE } = undefined;

        var token = self.toker.next();
        var keep_next = false; // Use in the loop to prevent to get the next token when continue. Just need to make it true and it is reset at every loop

        while (state != State.end) : ({
            token = if (!keep_next) self.toker.next() else token;
            keep_next = false;
            if (PRINT_STATE) std.debug.print("parse: {any}\n", .{state});
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
                if (!self.schema_engine.isStructNameExists(struct_name)) return printError(
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
                try self.parseAdditionalData(allocator, &additional_data, struct_name);
                state = switch (action) {
                    .GRAB => .filter_and_send,
                    .UPDATE => .filter_and_update,
                    .DELETE => .filter_and_delete,
                    else => unreachable,
                };
            },

            .filter_and_send => switch (token.tag) {
                .l_brace => {
                    var filter = try self.parseFilter(allocator, struct_name, false);
                    defer filter.deinit();

                    var buff = std.ArrayList(u8).init(allocator);
                    defer buff.deinit();

                    try self.file_engine.parseEntities(struct_name, filter, &additional_data, &buff.writer());
                    send("{s}", .{buff.items});
                    state = .end;
                },
                .eof => {
                    var buff = std.ArrayList(u8).init(allocator);
                    defer buff.deinit();

                    try self.file_engine.parseEntities(struct_name, null, &additional_data, &buff.writer());
                    send("{s}", .{buff.items});
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
                    var filter = try self.parseFilter(allocator, struct_name, false);
                    defer filter.deinit();

                    token = self.toker.last();

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

                    var data_map = std.StringHashMap(ConditionValue).init(allocator);
                    defer data_map.deinit();
                    try self.parseNewData(allocator, &data_map, struct_name);

                    var buff = std.ArrayList(u8).init(allocator);
                    defer buff.deinit();

                    try self.file_engine.updateEntities(struct_name, filter, data_map, &buff.writer(), &additional_data);
                    send("{s}", .{buff.items});
                    state = .end;
                },
                .keyword_to => {
                    token = self.toker.next();
                    if (token.tag != .l_paren) return printError(
                        "Error: Expected (",
                        ZiQlParserError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );

                    var data_map = std.StringHashMap(ConditionValue).init(allocator);
                    defer data_map.deinit();
                    try self.parseNewData(allocator, &data_map, struct_name);

                    var buff = std.ArrayList(u8).init(allocator);
                    defer buff.deinit();

                    try self.file_engine.updateEntities(struct_name, null, data_map, &buff.writer(), &additional_data);
                    send("{s}", .{buff.items});
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
                    var filter = try self.parseFilter(allocator, struct_name, false);
                    defer filter.deinit();

                    var buff = std.ArrayList(u8).init(allocator);
                    defer buff.deinit();

                    try self.file_engine.deleteEntities(struct_name, filter, &buff.writer(), &additional_data);
                    send("{s}", .{buff.items});
                    state = .end;
                },
                .eof => {
                    var buff = std.ArrayList(u8).init(allocator);
                    defer buff.deinit();

                    try self.file_engine.deleteEntities(struct_name, null, &buff.writer(), &additional_data);
                    send("{s}", .{buff.items});
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
                var data_map = std.StringHashMap(ConditionValue).init(allocator);
                defer data_map.deinit();
                try self.parseNewData(allocator, &data_map, struct_name);

                var error_message_buffer = std.ArrayList(u8).init(allocator);
                defer error_message_buffer.deinit();

                const error_message_buffer_writer = error_message_buffer.writer();
                error_message_buffer_writer.writeAll("Error missing: ") catch return ZipponError.WriteError;

                if (!(self.schema_engine.checkIfAllMemberInMap(struct_name, &data_map, &error_message_buffer) catch {
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
                var buff = std.ArrayList(u8).init(allocator);
                defer buff.deinit();

                token = self.toker.last_token;
                if (token.tag == .identifier and std.mem.eql(u8, self.toker.getTokenSlice(token), "TESTDATASET")) {
                    for (0..100) |_| self.file_engine.addEntity(struct_name, data_map, &buff.writer(), 10_000) catch return ZipponError.CantWriteEntity;
                } else {
                    self.file_engine.addEntity(struct_name, data_map, &buff.writer(), 1) catch return ZipponError.CantWriteEntity;
                }
                send("{s}", .{buff.items});
                state = .end;
            },

            else => unreachable,
        };
    }

    /// Take an array of UUID and populate it with what match what is between {}
    /// Main is to know if between {} or (), main is true if between {}, otherwise between () inside {}
    fn parseFilter(self: Parser, allocator: Allocator, struct_name: []const u8, is_sub: bool) ZipponError!Filter {
        var filter = try Filter.init(allocator);
        errdefer filter.deinit();

        var keep_next = false;
        var token = self.toker.next();
        var state: State = .expect_condition;

        while (state != .end) : ({
            token = if (keep_next) token else self.toker.next();
            keep_next = false;
            if (PRINT_STATE) std.debug.print("parseFilter: {any}\n", .{state});
        }) {
            switch (state) {
                .expect_condition => switch (token.tag) {
                    .r_brace => {
                        if (!is_sub) {
                            state = .end;
                        } else {
                            return printError(
                                "Error: Expected ) not }",
                                ZipponError.SynthaxError,
                                self.toker.buffer,
                                token.loc.start,
                                token.loc.end,
                            );
                        }
                    },
                    .r_paren => {
                        if (is_sub) {
                            state = .end;
                        } else {
                            return printError(
                                "Error: Expected } not )",
                                ZipponError.SynthaxError,
                                self.toker.buffer,
                                token.loc.start,
                                token.loc.end,
                            );
                        }
                    },
                    .l_paren => {
                        var sub_filter = try self.parseFilter(allocator, struct_name, true);
                        filter.addSubFilter(&sub_filter);
                        token = self.toker.last();
                        keep_next = true;
                        state = .expect_ANDOR_OR_end;
                    },
                    .identifier => {
                        const condition = try self.parseCondition(allocator, &token, struct_name);
                        try filter.addCondition(condition);
                        token = self.toker.last();
                        keep_next = true;
                        state = .expect_ANDOR_OR_end;
                    },
                    else => return printError(
                        "Error: Expected ( or condition.",
                        ZiQlParserError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    ),
                },

                .expect_ANDOR_OR_end => switch (token.tag) {
                    .r_brace => {
                        if (!is_sub) {
                            state = .end;
                        } else {
                            return printError(
                                "Error: Expected ) not }",
                                ZipponError.SynthaxError,
                                self.toker.buffer,
                                token.loc.start,
                                token.loc.end,
                            );
                        }
                    },
                    .r_paren => {
                        if (is_sub) {
                            state = .end;
                        } else {
                            return printError(
                                "Error: Expected } not )",
                                ZipponError.SynthaxError,
                                self.toker.buffer,
                                token.loc.start,
                                token.loc.end,
                            );
                        }
                    },
                    .keyword_and => {
                        try filter.addLogicalOperator(.AND);
                        state = .expect_condition;
                    },
                    .keyword_or => {
                        try filter.addLogicalOperator(.OR);
                        state = .expect_condition;
                    },
                    else => return printError(
                        "Error: Expected AND, OR, or }",
                        ZiQlParserError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    ),
                },

                else => unreachable,
            }
        }

        return filter;
    }

    /// Parse to get a Condition. Which is a struct that is use by the FileEngine to retreive data.
    /// In the query, it is this part name = 'Bob' or age <= 10
    fn parseCondition(self: Parser, allocator: Allocator, token_ptr: *Token, struct_name: []const u8) ZipponError!Condition {
        var keep_next = false;
        var state: State = .expect_member;
        var token = token_ptr.*;

        var condition = Condition{};

        while (state != .end) : ({
            token = if (!keep_next) self.toker.next() else token;
            keep_next = false;
            if (PRINT_STATE) std.debug.print("parseCondition: {any}\n", .{state});
        }) switch (state) {
            .expect_member => switch (token.tag) {
                .identifier => {
                    if (!(self.schema_engine.isMemberNameInStruct(struct_name, self.toker.getTokenSlice(token)) catch {
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
                    condition.data_type = self.schema_engine.memberName2DataType(
                        struct_name,
                        self.toker.getTokenSlice(token),
                    ) catch return ZiQlParserError.MemberNotFound;
                    condition.data_index = self.schema_engine.memberName2DataIndex(
                        struct_name,
                        self.toker.getTokenSlice(token),
                    ) catch return ZiQlParserError.MemberNotFound;
                    state = .expect_operation;
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
                condition.operation = try self.parseComparisonOperator(token);
                state = .expect_value;
            },

            .expect_value => {
                condition.value = try self.parseConditionValue(allocator, struct_name, condition.data_type, &token);
                state = .end;
            },

            else => unreachable,
        };

        try self.checkConditionValidity(condition, token);

        return condition;
    }

    /// Will check if what is compared is ok, like comparing if a string is superior to another string is not for example.
    fn checkConditionValidity(self: Parser, condition: Condition, token: Token) ZipponError!void {
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

            .in => switch (condition.data_type) {
                .link => {},
                else => return printError(
                    "Error: Only link can be compare with in for now.",
                    ZiQlParserError.ConditionError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },

            else => unreachable,
        }
    }

    /// When this function is call, next token should be [
    /// Check if an int is here -> check if ; is here -> check if member is here -> check if [ is here -> loop
    fn parseAdditionalData(self: Parser, allocator: Allocator, additional_data: *AdditionalData, struct_name: []const u8) ZipponError!void {
        var token = self.toker.next();
        var keep_next = false;
        var state: State = .expect_count_of_entity_to_find;

        while (state != .end) : ({
            token = if ((!keep_next) and (state != .end)) self.toker.next() else token;
            keep_next = false;
            if (PRINT_STATE) std.debug.print("parseAdditionalData: {any}\n", .{state});
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
                    if (!(self.schema_engine.isMemberNameInStruct(struct_name, self.toker.getTokenSlice(token)) catch {
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
                            allocator,
                            self.toker.getTokenSlice(token),
                            try self.schema_engine.memberName2DataIndex(struct_name, self.toker.getTokenSlice(token)),
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
                        allocator,
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
    fn parseNewData(self: Parser, allocator: Allocator, map: *std.StringHashMap(ConditionValue), struct_name: []const u8) !void {
        var token = self.toker.next();
        var keep_next = false;
        var member_name: []const u8 = undefined; // Maybe use allocator.alloc
        var state: State = .expect_member;

        while (state != .end) : ({
            token = if (!keep_next) self.toker.next() else token;
            keep_next = false;
            if (PRINT_STATE) std.debug.print("parseNewData: {any}\n", .{state});
        }) switch (state) {
            .expect_member => switch (token.tag) {
                .identifier => {
                    member_name = self.toker.getTokenSlice(token);
                    if (!(self.schema_engine.isMemberNameInStruct(struct_name, member_name) catch {
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
                const data_type = self.schema_engine.memberName2DataType(struct_name, member_name) catch return ZiQlParserError.StructNotFound;
                map.put(member_name, try self.parseConditionValue(allocator, struct_name, data_type, &token)) catch return ZipponError.MemoryError;
                if (data_type == .link or data_type == .link_array) {
                    token = self.toker.last_token;
                    keep_next = true;
                }
                state = .expect_comma_OR_end;
            },

            .expect_comma_OR_end => switch (token.tag) {
                .r_paren => state = .end,
                .comma => state = .expect_member,
                else => return printError(
                    "Error: Expect , or )",
                    ZiQlParserError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },

            else => unreachable,
        };
    }

    fn parseComparisonOperator(self: Parser, token: Token) ZipponError!ComparisonOperator {
        return switch (token.tag) {
            .equal => .equal, // =
            .angle_bracket_left => .inferior, // <
            .angle_bracket_right => .superior, // >
            .angle_bracket_left_equal => .inferior_or_equal, // <=
            .angle_bracket_right_equal => .superior_or_equal, // >=
            .bang_equal => .different, // !=
            .keyword_in => .in,
            .keyword_not_in => .not_in,
            else => return printError(
                "Error: Expected condition. Including < > <= >= = !=",
                ZiQlParserError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        };
    }

    /// To run just after a condition like = or > or >= to get the corresponding ConditionValue that you need to compare
    fn parseConditionValue(self: Parser, allocator: Allocator, struct_name: []const u8, data_type: dtype.DataType, token: *Token) ZipponError!ConditionValue {
        const start_index = token.loc.start;
        const expected_tag: ?Token.Tag = switch (data_type) {
            .int => .int_literal,
            .float => .float_literal,
            .str => .string_literal,
            .self => .uuid_literal,
            .date => .date_literal,
            .time => .time_literal,
            .datetime => .datetime_literal,
            .int_array => .int_literal,
            .float_array => .float_literal,
            .str_array => .string_literal,
            .date_array => .date_literal,
            .time_array => .time_literal,
            .datetime_array => .datetime_literal,
            .bool, .bool_array, .link, .link_array => null, // handle separately
        };

        // Check if the all next tokens are the right one
        if (expected_tag) |tag| {
            if (data_type.is_array()) {
                token.* = try self.checkTokensInArray(tag);
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
        } else switch (data_type) {
            .bool => {
                if (token.tag != .bool_literal_true and token.tag != .bool_literal_false) {
                    return printError(
                        "Error: Expected bool",
                        ZiQlParserError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );
                }
            },
            .bool_array => {
                token.* = self.toker.next();
                while (token.tag != .r_bracket) : (token.* = self.toker.next()) {
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
            },
            .link, .link_array => {}, // TODO: Check if next token is either [ or {
            else => unreachable,
        }

        // And finally create the ConditionValue
        var value: ConditionValue = undefined;
        switch (data_type) {
            .int => value = ConditionValue.initInt(self.toker.buffer[start_index..token.loc.end]),
            .float => value = ConditionValue.initFloat(self.toker.buffer[start_index..token.loc.end]),
            .str => value = ConditionValue.initStr(self.toker.buffer[start_index + 1 .. token.loc.end - 1]),
            .date => value = ConditionValue.initDate(self.toker.buffer[start_index..token.loc.end]),
            .time => value = ConditionValue.initTime(self.toker.buffer[start_index..token.loc.end]),
            .datetime => value = ConditionValue.initDateTime(self.toker.buffer[start_index..token.loc.end]),
            .bool => value = ConditionValue.initBool(self.toker.buffer[start_index..token.loc.end]),
            .int_array => value = try ConditionValue.initArrayInt(allocator, self.toker.buffer[start_index..token.loc.end]),
            .str_array => value = try ConditionValue.initArrayStr(allocator, self.toker.buffer[start_index..token.loc.end]),
            .bool_array => value = try ConditionValue.initArrayBool(allocator, self.toker.buffer[start_index..token.loc.end]),
            .float_array => value = try ConditionValue.initArrayFloat(allocator, self.toker.buffer[start_index..token.loc.end]),
            .date_array => value = try ConditionValue.initArrayDate(allocator, self.toker.buffer[start_index..token.loc.end]),
            .time_array => value = try ConditionValue.initArrayTime(allocator, self.toker.buffer[start_index..token.loc.end]),
            .datetime_array => value = try ConditionValue.initArrayDateTime(allocator, self.toker.buffer[start_index..token.loc.end]),
            .link_array, .link => switch (token.tag) {
                .keyword_none => {
                    const map = allocator.create(std.AutoHashMap(UUID, void)) catch return ZipponError.MemoryError;
                    map.* = std.AutoHashMap(UUID, void).init(allocator);
                    _ = map.getOrPut(UUID.parse("00000000-0000-0000-0000-000000000000") catch @panic("Sorry wot ?")) catch return ZipponError.MemoryError;
                    value = ConditionValue.initLink(map);
                    _ = self.toker.next();
                },
                .uuid_literal => {
                    const uuid = UUID.parse(self.toker.buffer[start_index..token.loc.end]) catch return ZipponError.InvalidUUID;
                    if (!self.schema_engine.isUUIDExist(struct_name, uuid)) return printError(
                        "Error: UUID do not exist in database.",
                        ZiQlParserError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );

                    const map = allocator.create(std.AutoHashMap(UUID, void)) catch return ZipponError.MemoryError;
                    map.* = std.AutoHashMap(UUID, void).init(allocator);
                    _ = map.getOrPut(uuid) catch return ZipponError.MemoryError;
                    value = ConditionValue.initLink(map);
                    _ = self.toker.next();
                },
                .l_brace, .l_bracket => {
                    var filter: ?Filter = null;
                    defer if (filter != null) filter.?.deinit();
                    var additional_data = AdditionalData.init(allocator);
                    defer additional_data.deinit();

                    if (token.tag == .l_bracket) {
                        try self.parseAdditionalData(allocator, &additional_data, struct_name);
                        token.* = self.toker.next();
                    }

                    if (data_type == .link) additional_data.entity_count_to_find = 1;

                    if (token.tag == .l_brace) filter = try self.parseFilter(allocator, struct_name, false) else return printError(
                        "Error: Expected filter",
                        ZiQlParserError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );

                    // Here I have the filter and additionalData
                    const map = allocator.create(std.AutoHashMap(UUID, void)) catch return ZipponError.MemoryError;
                    map.* = std.AutoHashMap(UUID, void).init(allocator);
                    try self.file_engine.populateVoidUUIDMap(
                        struct_name,
                        filter,
                        map,
                        &additional_data,
                    );
                    log.debug("Found {d} entity when parsing for populateVoidUUID\n", .{map.count()});
                    value = ConditionValue.initLink(map);
                },
                else => return printError(
                    "Error: Expected uuid or none",
                    ZiQlParserError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },
            else => unreachable,
        }

        return value;
    }

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
    try testParsing("ADD User (name = 'Bob', email='bob@email.com', age=55, scores=[ 1 ], best_friend=none, bday=2000/01/01, a_time=12:04, last_order=2000/01/01-12:45)");
    try testParsing("ADD User (name = 'Bob', email='bob@email.com', age=55, scores=[ 666 123 331 ], best_friend=none, bday=2000/01/01, a_time=12:04:54, last_order=2000/01/01-12:45)");
    try testParsing("ADD User (name = 'Bob', email='bob@email.com', age=-55, scores=[ 33 ], best_friend=none, bday=2000/01/01, a_time=12:04:54.8741, last_order=2000/01/01-12:45)");
    try testParsing("ADD User (name = 'Boba', email='boba@email.com', age=20, scores=[ ], best_friend=none, bday=2000/01/01, a_time=12:04:54.8741, last_order=2000/01/01-12:45)");

    // This need to take the first User named Bob as it is a unique link
    try testParsing("ADD User (name = 'Bob', email='bob@email.com', age=-55, scores=[ 1 ], best_friend={name = 'Bob'}, bday=2000/01/01, a_time=12:04:54.8741, last_order=2000/01/01-12:45)");
}

test "GRAB filter with string" {
    try testParsing("GRAB User {name = 'Bob'}");
    try testParsing("GRAB User {name != 'Brittany Rogers'}");
}

test "GRAB with additional data" {
    try testParsing("GRAB User [1] {age < 18}");
    try testParsing("GRAB User [id, name] {age < 18}");
    try testParsing("GRAB User [100; name] {age < 18}");
}

test "UPDATE" {
    try testParsing("UPDATE User {name = 'Bob'} TO (email='new@gmail.com')");
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

// TODO: next step is to make this work

test "UPDATE relationship" {
    try testParsing("UPDATE User [1] {} TO (best_friend = {name='Boba'} )");
    try testParsing("GRAB User {best_friend IN {name = 'Boba'}}"); // Not yet working
}

//test "GRAB Relationship" {
//    try testParsing("GRAB User {best_friend IN {name = 'Bob'}}");
//}

test "DELETE" {
    try testParsing("DELETE User {name='Bob'}");
}

test "Synthax error" {
    try expectParsingError("ADD User (name = 'Bob', email='bob@email.com', age=-55, scores=[ 1 ], best_friend=7db1f06d-a5a7-4917-8cc6-4d490191c9c1, bday=2000/01/01, a_time=12:04:54.8741, last_order=2000/01/01-12:45)", ZiQlParserError.SynthaxError);
    try expectParsingError("GRAB {}", ZiQlParserError.StructNotFound);
    try expectParsingError("GRAB User {qwe = 'qwe'}", ZiQlParserError.MemberNotFound);
    try expectParsingError("ADD User (name='Bob')", ZiQlParserError.MemberMissing);
    try expectParsingError("GRAB User {name='Bob'", ZiQlParserError.SynthaxError);
    try expectParsingError("GRAB User {age = 50 name='Bob'}", ZiQlParserError.SynthaxError);
    try expectParsingError("GRAB User {age <14 AND (age>55}", ZiQlParserError.SynthaxError);
    try expectParsingError("GRAB User {name < 'Hello'}", ZiQlParserError.ConditionError);
}

const DBEngine = @import("main.zig").DBEngine;

fn testParsing(source: [:0]const u8) !void {
    const TEST_DATA_DIR = @import("config.zig").TEST_DATA_DIR;

    var db_engine = DBEngine.init(TEST_DATA_DIR, null);
    defer db_engine.deinit();

    var toker = Tokenizer.init(source);
    var parser = Parser.init(
        &toker,
        &db_engine.file_engine,
        &db_engine.schema_engine,
    );

    try parser.parse();
}

fn expectParsingError(source: [:0]const u8, err: ZiQlParserError) !void {
    const TEST_DATA_DIR = @import("config.zig").TEST_DATA_DIR;

    var db_engine = DBEngine.init(TEST_DATA_DIR, null);
    defer db_engine.deinit();

    var toker = Tokenizer.init(source);
    var parser = Parser.init(
        &toker,
        &db_engine.file_engine,
        &db_engine.schema_engine,
    );

    try std.testing.expectError(err, parser.parse());
}

test "Parse filter" {
    try testParseFilter("name = 'Adrien'}");
    try testParseFilter("name = 'Adrien' AND age > 11}");
    try testParseFilter("name = 'Adrien' AND (age < 11 OR age > 40)}");
    try testParseFilter("(name = 'Adrien') AND (age < 11 OR age > 40)}");
    try testParseFilter("(name = 'Adrien' OR name = 'Bob') AND (age < 11 OR age > 40)}");
    try testParseFilter("(name = 'Adrien' OR name = 'Bob') AND (age < 11 OR age > 40 AND (age != 20))}");
}

fn testParseFilter(source: [:0]const u8) !void {
    const TEST_DATA_DIR = @import("config.zig").TEST_DATA_DIR;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var db_engine = DBEngine.init(TEST_DATA_DIR, null);
    defer db_engine.deinit();

    var toker = Tokenizer.init(source);
    var parser = Parser.init(
        &toker,
        &db_engine.file_engine,
        &db_engine.schema_engine,
    );

    var filter = try parser.parseFilter(allocator, "User", false);
    defer filter.deinit();
    std.debug.print("{s}\n", .{source});
    filter.debugPrint();
}
