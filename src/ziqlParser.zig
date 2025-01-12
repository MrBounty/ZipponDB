const std = @import("std");
const Allocator = std.mem.Allocator;
const FileEngine = @import("fileEngine/core.zig");
const SchemaEngine = @import("schemaEngine.zig").SchemaEngine;
const Tokenizer = @import("tokenizers/ziql.zig").Tokenizer;
const Token = @import("tokenizers/ziql.zig").Token;

const dtype = @import("dtype");
const UUID = dtype.UUID;

const Filter = @import("dataStructure/filter.zig").Filter;
const Condition = @import("dataStructure/filter.zig").Condition;
const ConditionValue = @import("dataStructure/filter.zig").ConditionValue;
const ComparisonOperator = @import("dataStructure/filter.zig").ComparisonOperator;

const AdditionalData = @import("dataStructure/additionalData.zig").AdditionalData;
const AdditionalDataMember = @import("dataStructure/additionalData.zig").AdditionalDataMember;
const send = @import("utils.zig").send;
const printError = @import("utils.zig").printError;

const ZipponError = @import("error").ZipponError;
const PRINT_STATE = @import("config").PRINT_STATE;

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
    expect_limit,
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
    expect_member_OR_value,
    expect_equal,
    expect_new_value,
    expect_comma_OR_end,
    add_member_to_map,
    add_array_to_map,
};

pub const Parser = @This();

toker: *Tokenizer,
file_engine: *FileEngine,
schema_engine: *SchemaEngine,

pub fn init(toker: *Tokenizer, file_engine: *FileEngine, schema_engine: *SchemaEngine) Parser {
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
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },

        .expect_struct_name => {
            // Check if the struct name is in the schema
            struct_name = self.toker.getTokenSlice(token);
            if (token.tag != .identifier) return printError(
                "Error: Missing struct name.",
                ZipponError.StructNotFound,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            );
            if (!self.schema_engine.isStructNameExists(struct_name)) return printError(
                "Error: struct name not found in schema.",
                ZipponError.StructNotFound,
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
                .l_brace, .eof => state = switch (action) {
                    .GRAB => .filter_and_send,
                    .UPDATE => .filter_and_update,
                    .DELETE => .filter_and_delete,
                    else => unreachable,
                },
                else => return printError(
                    "Error: Expect [ for additional data or { for a filter",
                    ZipponError.SynthaxError,
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

                const json_string = try self.file_engine.parseEntities(struct_name, filter, &additional_data, allocator);
                send("{s}", .{json_string});
                state = .end;
            },
            .eof => {
                const json_string = try self.file_engine.parseEntities(struct_name, null, &additional_data, allocator);
                send("{s}", .{json_string});
                state = .end;
            },
            else => return printError(
                "Error: Expected filter.",
                ZipponError.SynthaxError,
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
                    ZipponError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                );

                token = self.toker.next();
                if (token.tag != .l_paren) return printError(
                    "Error: Expected (",
                    ZipponError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                );

                var data_map = std.StringHashMap(ConditionValue).init(allocator);
                defer data_map.deinit();
                try self.parseNewData(allocator, &data_map, struct_name, null, null);

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
                    ZipponError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                );

                var data_map = std.StringHashMap(ConditionValue).init(allocator);
                defer data_map.deinit();
                try self.parseNewData(allocator, &data_map, struct_name, null, null);

                var buff = std.ArrayList(u8).init(allocator);
                defer buff.deinit();

                try self.file_engine.updateEntities(struct_name, null, data_map, &buff.writer(), &additional_data);
                send("{s}", .{buff.items});
                state = .end;
            },
            else => return printError(
                "Error: Expected filter or TO.",
                ZipponError.SynthaxError,
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
                ZipponError.SynthaxError,
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
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },

        .parse_new_data_and_add_data => {
            var order = std.ArrayList([]const u8).init(allocator);
            defer order.deinit();
            var ordered = false;

            var buff = std.ArrayList(u8).init(allocator);
            defer buff.deinit();
            buff.writer().writeAll("[") catch return ZipponError.WriteError;

            var maps = std.ArrayList(std.StringHashMap(ConditionValue)).init(allocator);
            defer maps.deinit();

            var local_arena = std.heap.ArenaAllocator.init(allocator);
            defer local_arena.deinit();
            const local_allocator = arena.allocator();

            var data_map = std.StringHashMap(ConditionValue).init(allocator);
            defer data_map.deinit();

            while (true) { // I could multithread that as it do take a long time for big benchmark
                data_map.clearRetainingCapacity();
                try self.parseNewData(local_allocator, &data_map, struct_name, &order, ordered);
                ordered = true;

                var error_message_buffer = std.ArrayList(u8).init(local_allocator);
                defer error_message_buffer.deinit();

                const error_message_buffer_writer = error_message_buffer.writer();
                error_message_buffer_writer.writeAll("Error missing: ") catch return ZipponError.WriteError;

                if (!(self.schema_engine.checkIfAllMemberInMap(struct_name, &data_map, &error_message_buffer) catch {
                    return ZipponError.StructNotFound;
                })) {
                    _ = error_message_buffer.pop();
                    _ = error_message_buffer.pop();
                    return printError(
                        error_message_buffer.items,
                        ZipponError.MemberMissing,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );
                }

                maps.append(data_map.cloneWithAllocator(local_allocator) catch return ZipponError.MemoryError) catch return ZipponError.MemoryError;

                if (maps.items.len >= 1_000) {
                    self.file_engine.addEntity(struct_name, maps.items, &buff.writer()) catch return ZipponError.CantWriteEntity;
                    maps.clearRetainingCapacity();
                    _ = local_arena.reset(.retain_capacity);
                }

                token = self.toker.last_token;
                if (token.tag == .l_paren) continue;
                break;
            }

            self.file_engine.addEntity(struct_name, maps.items, &buff.writer()) catch return ZipponError.CantWriteEntity;

            buff.writer().writeAll("]") catch return ZipponError.WriteError;
            send("{s}", .{buff.items});
            state = .end;
        },

        else => unreachable,
    };
}

/// Take an array of UUID and populate it with what match what is between {}
/// Main is to know if between {} or (), main is true if between {}, otherwise between () inside {}
pub fn parseFilter(self: Parser, allocator: Allocator, struct_name: []const u8, is_sub: bool) ZipponError!Filter {
    var filter = try Filter.init(allocator);
    errdefer filter.deinit();

    var keep_next = false;
    var token = self.toker.next();
    var state: State = .expect_condition;

    while (state != .end) : ({
        token = if (keep_next) token else self.toker.next();
        keep_next = false;
        if (PRINT_STATE) std.debug.print("parseFilter: {any}\n", .{state});
    }) switch (state) {
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
                ZipponError.SynthaxError,
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
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },

        .end => {},

        else => unreachable,
    };

    return filter;
}

/// Parse to get a Condition. Which is a struct that is use by the FileEngine to retreive data.
/// In the query, it is this part name = 'Bob' or age <= 10
fn parseCondition(self: Parser, allocator: Allocator, token_ptr: *Token, struct_name: []const u8) ZipponError!Condition {
    var keep_next = false;
    var state: State = .expect_member;
    var token = token_ptr.*;
    var member_name: []const u8 = undefined;

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
                        ZipponError.StructNotFound,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );
                })) {
                    return printError(
                        "Error: Member not part of struct.",
                        ZipponError.MemberNotFound,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );
                }
                condition.data_type = self.schema_engine.memberName2DataType(
                    struct_name,
                    self.toker.getTokenSlice(token),
                ) catch return ZipponError.MemberNotFound;
                condition.data_index = self.schema_engine.memberName2DataIndex(
                    struct_name,
                    self.toker.getTokenSlice(token),
                ) catch return ZipponError.MemberNotFound;
                member_name = self.toker.getTokenSlice(token);
                state = .expect_operation;
            },
            else => return printError(
                "Error: Expected member name.",
                ZipponError.SynthaxError,
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
            log.debug("Parse condition value of member {s}", .{member_name});
            condition.value = try self.parseConditionValue(allocator, struct_name, member_name, condition.data_type, &token);
            state = .end;
        },

        else => unreachable,
    };

    try self.checkConditionValidity(condition, token);

    return condition;
}

/// Will check if what is compared is ok, like comparing if a string is superior to another string is not for example.
fn checkConditionValidity(
    self: Parser,
    condition: Condition,
    token: Token,
) ZipponError!void {
    switch (condition.operation) {
        .equal => switch (condition.data_type) {
            .int, .float, .str, .bool, .date, .time, .datetime => {},
            else => return printError(
                "Error: Only int, float, str, bool, date, time, datetime can be compare with =",
                ZipponError.ConditionError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },

        .different => switch (condition.data_type) {
            .int, .float, .str, .bool, .date, .time, .datetime => {},
            else => return printError(
                "Error: Only int, float, str, bool, date, time, datetime can be compare with !=",
                ZipponError.ConditionError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },

        .superior_or_equal => switch (condition.data_type) {
            .int, .float, .date, .time, .datetime => {},
            else => return printError(
                "Error: Only int, float, date, time, datetime can be compare with >=",
                ZipponError.ConditionError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },

        .superior => switch (condition.data_type) {
            .int, .float, .date, .time, .datetime => {},
            else => return printError(
                "Error: Only int, float, date, time, datetime can be compare with >",
                ZipponError.ConditionError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },

        .inferior_or_equal => switch (condition.data_type) {
            .int, .float, .date, .time, .datetime => {},
            else => return printError(
                "Error: Only int, float, date, time, datetime can be compare with <=",
                ZipponError.ConditionError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },

        .inferior => switch (condition.data_type) {
            .int, .float, .date, .time, .datetime => {},
            else => return printError(
                "Error: Only int, float, date, time, datetime can be compare with <",
                ZipponError.ConditionError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },

        .in => switch (condition.data_type) {
            .link => {},
            else => return printError(
                "Error: Only link can be compare with IN.",
                ZipponError.ConditionError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },

        .not_in => switch (condition.data_type) {
            .link => {},
            else => return printError(
                "Error: Only link can be compare with !IN.",
                ZipponError.ConditionError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },
    }
}

/// When this function is call, next token should be [
/// Check if an int is here -> check if ; is here -> check if member is here -> check if [ is here -> loop
fn parseAdditionalData(
    self: Parser,
    allocator: Allocator,
    additional_data: *AdditionalData,
    struct_name: []const u8,
) ZipponError!void {
    var token = self.toker.next();
    var keep_next = false;
    var state: State = .expect_limit;
    var last_member: []const u8 = undefined;

    while (state != .end) : ({
        token = if ((!keep_next) and (state != .end)) self.toker.next() else token;
        keep_next = false;
        if (PRINT_STATE) std.debug.print("parseAdditionalData: {any}\n", .{state});
    }) switch (state) {
        .expect_limit => switch (token.tag) {
            .int_literal => {
                additional_data.limit = std.fmt.parseInt(usize, self.toker.getTokenSlice(token), 10) catch {
                    return printError(
                        "Error while transforming limit into a integer.",
                        ZipponError.ParsingValueError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );
                };
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
                ZipponError.SynthaxError,
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
                        ZipponError.StructNotFound,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );
                })) {
                    return printError(
                        "Member not found in struct.",
                        ZipponError.MemberNotFound,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );
                }
                try additional_data.addMember(
                    self.toker.getTokenSlice(token),
                    try self.schema_engine.memberName2DataIndex(struct_name, self.toker.getTokenSlice(token)),
                );
                last_member = self.toker.getTokenSlice(token);

                state = .expect_comma_OR_r_bracket_OR_l_bracket;
            },
            else => return printError(
                "Error: Expected a member name.",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },

        .expect_comma_OR_r_bracket_OR_l_bracket => switch (token.tag) {
            .comma => state = .expect_member,
            .r_bracket => state = .end,
            .l_bracket => {
                const sstruct = try self.schema_engine.structName2SchemaStruct(struct_name);
                try self.parseAdditionalData(
                    allocator,
                    &additional_data.childrens.items[additional_data.childrens.items.len - 1].additional_data,
                    sstruct.links.get(last_member).?,
                );
                state = .expect_comma_OR_r_bracket;
            },
            else => return printError(
                "Error: Expected , or ] or [",
                ZipponError.SynthaxError,
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
                ZipponError.SynthaxError,
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
fn parseNewData(
    self: Parser,
    allocator: Allocator,
    map: *std.StringHashMap(ConditionValue),
    struct_name: []const u8,
    order: ?*std.ArrayList([]const u8),
    order_full: ?bool,
) !void {
    var token = self.toker.next();
    var keep_next = false;
    var member_name: []const u8 = undefined;
    var state: State = .expect_member_OR_value;
    var i: usize = 0;

    while (state != .end) : ({
        token = if (!keep_next) self.toker.next() else token;
        keep_next = false;
        if (PRINT_STATE) std.debug.print("parseNewData: {any}\n", .{state});
    }) switch (state) {
        .expect_member_OR_value => switch (token.tag) {
            .identifier => {
                member_name = self.toker.getTokenSlice(token);
                if (!(self.schema_engine.isMemberNameInStruct(struct_name, member_name) catch {
                    return ZipponError.StructNotFound;
                })) return printError(
                    "Member not found in struct.",
                    ZipponError.MemberNotFound,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                );
                if (order_full) |o| if (!o) order.?.*.append(allocator.dupe(u8, member_name) catch return ZipponError.MemoryError) catch return ZipponError.MemoryError;
                state = .expect_equal;
            },
            .string_literal,
            .int_literal,
            .float_literal,
            .date_literal,
            .time_literal,
            .datetime_literal,
            .bool_literal_true,
            .bool_literal_false,
            .uuid_literal,
            .l_bracket,
            .l_brace,
            .keyword_none,
            .keyword_now,
            => if (order_full) |o| {
                if (!o) return printError(
                    "Expected member name.",
                    ZipponError.MemberMissing,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                );

                member_name = order.?.items[i];
                i += 1;
                keep_next = true;
                state = .expect_new_value;
            } else {
                return printError(
                    "Expected member name.",
                    ZipponError.MemberMissing,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                );
            },
            else => return printError(
                "Error: Expected member name.",
                ZipponError.SynthaxError,
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
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },

        .expect_new_value => {
            const data_type = self.schema_engine.memberName2DataType(struct_name, member_name) catch return ZipponError.StructNotFound;
            map.put(member_name, try self.parseConditionValue(allocator, struct_name, member_name, data_type, &token)) catch return ZipponError.MemoryError;
            if (data_type == .link or data_type == .link_array) {
                token = self.toker.last_token;
                keep_next = true;
            }
            state = .expect_comma_OR_end;
        },

        .expect_comma_OR_end => switch (token.tag) {
            .r_paren => state = .end,
            .comma => state = .expect_member_OR_value,
            else => return printError(
                "Error: Expect , or )",
                ZipponError.SynthaxError,
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
            ZipponError.SynthaxError,
            self.toker.buffer,
            token.loc.start,
            token.loc.end,
        ),
    };
}

/// To run just after a condition like = or > or >= to get the corresponding ConditionValue that you need to compare
fn parseConditionValue(self: Parser, allocator: Allocator, struct_name: []const u8, member_name: []const u8, data_type: dtype.DataType, token: *Token) ZipponError!ConditionValue {
    const start_index = token.loc.start;
    const expected_tag: ?Token.Tag = switch (data_type) {
        .int => .int_literal,
        .float => .float_literal,
        .str => .string_literal,
        .self => .uuid_literal,
        .int_array => .int_literal,
        .float_array => .float_literal,
        .str_array => .string_literal,
        .bool, .bool_array, .link, .link_array, .date, .time, .datetime, .date_array, .time_array, .datetime_array => null, // handle separately
    };

    // Check if the all next tokens are the right one
    if (expected_tag) |tag| {
        if (data_type.is_array()) {
            token.* = try self.checkTokensInArray(tag);
        } else {
            if (token.tag != tag) {
                return printError(
                    "Error: Wrong type", // TODO: Print the expected type
                    ZipponError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                );
            }
        }
    } else switch (data_type) {
        .bool => if (token.tag != .bool_literal_true and token.tag != .bool_literal_false) {
            return printError(
                "Error: Expected bool",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            );
        },
        .bool_array => {
            token.* = self.toker.next();
            while (token.tag != .r_bracket) : (token.* = self.toker.next()) {
                if (token.tag != .bool_literal_true and token.tag != .bool_literal_false) {
                    return printError(
                        "Error: Expected bool or ]",
                        ZipponError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );
                }
            }
        },
        .date => if (token.tag != .date_literal and token.tag != .keyword_now) {
            return printError(
                "Error: Expected date",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            );
        },
        .date_array => {
            token.* = self.toker.next();
            while (token.tag != .r_bracket) : (token.* = self.toker.next()) {
                if (token.tag != .date_literal and token.tag != .keyword_now) {
                    return printError(
                        "Error: Expected date",
                        ZipponError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );
                }
            }
        },
        .time => if (token.tag != .time_literal and token.tag != .keyword_now) {
            return printError(
                "Error: Expected time",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            );
        },
        .time_array => {
            token.* = self.toker.next();
            while (token.tag != .r_bracket) : (token.* = self.toker.next()) {
                if (token.tag != .time_literal and token.tag != .keyword_now) {
                    return printError(
                        "Error: Expected time",
                        ZipponError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );
                }
            }
        },
        .datetime => if (token.tag != .datetime_literal and token.tag != .keyword_now) {
            return printError(
                "Error: Expected datetime",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            );
        },
        .datetime_array => {
            token.* = self.toker.next();
            while (token.tag != .r_bracket) : (token.* = self.toker.next()) {
                if (token.tag != .datetime_literal and token.tag != .keyword_now) {
                    return printError(
                        "Error: Expected datetime",
                        ZipponError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );
                }
            }
        },
        .link, .link_array => {},
        else => unreachable,
    }

    // And finally create the ConditionValue
    switch (data_type) {
        .int => return ConditionValue.initInt(self.toker.buffer[start_index..token.loc.end]),
        .float => return ConditionValue.initFloat(self.toker.buffer[start_index..token.loc.end]),
        .str => return ConditionValue.initStr(self.toker.buffer[start_index + 1 .. token.loc.end - 1]),
        .date => return ConditionValue.initDate(self.toker.buffer[start_index..token.loc.end]),
        .time => return ConditionValue.initTime(self.toker.buffer[start_index..token.loc.end]),
        .datetime => return ConditionValue.initDateTime(self.toker.buffer[start_index..token.loc.end]),
        .bool => return ConditionValue.initBool(self.toker.buffer[start_index..token.loc.end]),
        .int_array => return try ConditionValue.initArrayInt(allocator, self.toker.buffer[start_index..token.loc.end]),
        .str_array => return try ConditionValue.initArrayStr(allocator, self.toker.buffer[start_index..token.loc.end]),
        .bool_array => return try ConditionValue.initArrayBool(allocator, self.toker.buffer[start_index..token.loc.end]),
        .float_array => return try ConditionValue.initArrayFloat(allocator, self.toker.buffer[start_index..token.loc.end]),
        .date_array => return try ConditionValue.initArrayDate(allocator, self.toker.buffer[start_index..token.loc.end]),
        .time_array => return try ConditionValue.initArrayTime(allocator, self.toker.buffer[start_index..token.loc.end]),
        .datetime_array => return try ConditionValue.initArrayDateTime(allocator, self.toker.buffer[start_index..token.loc.end]),
        .link => switch (token.tag) {
            .keyword_none => { // TODO: Stop creating a map if empty, can be null or something. Or maybe just keep one map link that in memory, so I dont create it everytime
                const map = allocator.create(std.AutoHashMap(UUID, void)) catch return ZipponError.MemoryError;
                map.* = std.AutoHashMap(UUID, void).init(allocator);
                map.put(dtype.Zero, {}) catch return ZipponError.MemoryError;
                _ = self.toker.next();
                return ConditionValue.initLink(map);
            },
            .uuid_literal => {
                const uuid = UUID.parse(self.toker.buffer[start_index..token.loc.end]) catch return ZipponError.InvalidUUID;
                if (!self.schema_engine.isUUIDExist(struct_name, uuid)) return printError(
                    "Error: UUID do not exist in database.",
                    ZipponError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                );

                const map = allocator.create(std.AutoHashMap(UUID, void)) catch return ZipponError.MemoryError;
                map.* = std.AutoHashMap(UUID, void).init(allocator);
                map.put(uuid, {}) catch return ZipponError.MemoryError;
                _ = self.toker.next();
                return ConditionValue.initLink(map);
            },
            .l_brace, .l_bracket => {
                var filter: ?Filter = null;
                defer if (filter != null) filter.?.deinit();

                var additional_data_arena = std.heap.ArenaAllocator.init(allocator);
                defer additional_data_arena.deinit();
                var additional_data = AdditionalData.init(additional_data_arena.allocator());

                if (token.tag == .l_bracket) {
                    try self.parseAdditionalData(allocator, &additional_data, struct_name);
                    token.* = self.toker.next();
                }

                additional_data.limit = 1;

                const link_sstruct = try self.schema_engine.linkedStructName(struct_name, member_name);
                if (token.tag == .l_brace) filter = try self.parseFilter(
                    allocator,
                    link_sstruct.name,
                    false,
                ) else return printError(
                    "Error: Expected filter",
                    ZipponError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                );

                filter = switch (filter.?.root.*) {
                    .empty => null,
                    else => filter,
                };

                // Here I have the filter and additionalData
                const map = allocator.create(std.AutoHashMap(UUID, void)) catch return ZipponError.MemoryError;
                map.* = std.AutoHashMap(UUID, void).init(allocator);
                try self.file_engine.populateVoidUUIDMap(
                    link_sstruct.name,
                    filter,
                    map,
                    &additional_data,
                );
                return ConditionValue.initLink(map);
            },

            else => return printError(
                "Error: Expected uuid or none",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },
        .link_array => switch (token.tag) {
            .keyword_none => {
                const map = allocator.create(std.AutoHashMap(UUID, void)) catch return ZipponError.MemoryError;
                map.* = std.AutoHashMap(UUID, void).init(allocator);
                _ = self.toker.next();
                return ConditionValue.initArrayLink(map);
            },
            .l_brace, .l_bracket => {
                var filter: ?Filter = null;
                defer if (filter != null) filter.?.deinit();

                var additional_data_arena = std.heap.ArenaAllocator.init(allocator);
                defer additional_data_arena.deinit();
                var additional_data = AdditionalData.init(additional_data_arena.allocator());

                if (token.tag == .l_bracket) {
                    try self.parseAdditionalData(allocator, &additional_data, struct_name);
                    token.* = self.toker.next();
                }

                const link_sstruct = try self.schema_engine.linkedStructName(struct_name, member_name);
                if (token.tag == .l_brace) filter = try self.parseFilter(allocator, link_sstruct.name, false) else return printError(
                    "Error: Expected filter",
                    ZipponError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                );

                filter = switch (filter.?.root.*) {
                    .empty => null,
                    else => filter,
                };

                // Here I have the filter and additionalData
                const map = allocator.create(std.AutoHashMap(UUID, void)) catch return ZipponError.MemoryError;
                map.* = std.AutoHashMap(UUID, void).init(allocator);
                try self.file_engine.populateVoidUUIDMap(
                    struct_name,
                    filter,
                    map,
                    &additional_data,
                );
                return ConditionValue.initArrayLink(map);
            },
            else => return printError(
                "Error: Expected uuid or none",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },
        .self => unreachable,
    }
}

/// Check if all token in an array is of one specific type
fn checkTokensInArray(self: Parser, tag: Token.Tag) ZipponError!Token {
    var token = self.toker.next();
    while (token.tag != .r_bracket) : (token = self.toker.next()) {
        if (token.tag != tag) return printError(
            "Error: Wrong type.",
            ZipponError.SynthaxError,
            self.toker.buffer,
            token.loc.start,
            token.loc.end,
        );
    }
    return token;
}
