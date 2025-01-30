const std = @import("std");
const config = @import("config");
const DataType = @import("dtype").DataType;
const Allocator = std.mem.Allocator;
const ConditionValue = @import("../../dataStructure/filter.zig").ConditionValue;
const printError = @import("../../utils.zig").printError;

const ZipponError = @import("error").ZipponError;

const Self = @import("../parser.zig");

// Ok so now for array how do I do. Because the map will not work anymore.
// I guess I change the map member_name -> ConditionValue. The ConditionValue can become an enum, either COnditionValue either a new struct
// The new struct need to have the operation (append, clear, etc) and a piece of data. The data can either be a single ConditionValue or an array of it.
// Or maybe just an array, it can be an array of 1 value.
// Like that I just need do add some switch on the enum to make it work

// I dont really like that ValueOrArray. I like how it work but not how I implemented it.
// I need to see if I can just make it a bit more simple and readable.
// Maybe make it's own file ?

pub const ValueOrArray = union(enum) {
    value: ConditionValue,
    array: ArrayUpdate,
};

pub const ArrayCondition = enum { append, clear, pop, remove, removeat };

pub const ArrayUpdate = struct {
    condition: ArrayCondition,
    data: ?ConditionValue,
};

/// Take the tokenizer and return a map of the ADD action.
/// Keys are the member name and value are the string of the value in the query. E.g. 'Adrien' or '10'
/// Entry token need to be (
pub fn parseNewData(
    self: Self,
    allocator: Allocator,
    map: *std.StringHashMap(ValueOrArray),
    struct_name: []const u8,
    order: *std.ArrayList([]const u8),
    for_update: bool,
) !void {
    var token = self.toker.next();
    var keep_next = false;
    var reordering: bool = false;
    var member_name: []const u8 = undefined;
    var state: Self.State = .expect_member_OR_value;
    var i: usize = 0;

    while (state != .end) : ({
        token = if (!keep_next) self.toker.next() else token;
        keep_next = false;
        if (config.PRINT_STATE) std.debug.print("parseNewData: {any}\n", .{state});
    }) switch (state) {
        .expect_member_OR_value => switch (token.tag) {
            .identifier => {
                if (!reordering) {
                    order.*.clearRetainingCapacity();
                    reordering = true;
                }
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
                order.*.append(allocator.dupe(u8, member_name) catch return ZipponError.MemoryError) catch return ZipponError.MemoryError;
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
            => {
                member_name = order.items[i];
                i += 1;
                keep_next = true;
                state = .expect_new_value;
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
            .equal => state = .expect_new_value,
            .keyword_pop => if (for_update) {
                map.put(
                    member_name,
                    ValueOrArray{ .array = .{ .condition = .pop, .data = null } },
                ) catch return ZipponError.MemoryError;
                state = .expect_comma_OR_end;
            } else return printError(
                "Error: Can only manipulate array with UPDATE.",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
            .keyword_clear => if (for_update) {
                map.put(
                    member_name,
                    ValueOrArray{ .array = .{ .condition = .clear, .data = null } },
                ) catch return ZipponError.MemoryError;
                state = .expect_comma_OR_end;
            } else return printError(
                "Error: Can only manipulate array with UPDATE.",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
            .keyword_append => if (for_update) {
                state = .expect_new_array;
            } else return printError(
                "Error: Can only manipulate array with UPDATE.",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
            .keyword_remove => if (for_update) {
                state = .expect_new_array;
            } else return printError(
                "Error: Can only manipulate array with UPDATE.",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
            .keyword_remove_at => if (for_update) {
                state = .expect_new_array;
            } else return printError(
                "Error: Can only manipulate array with UPDATE.",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
            else => return printError(
                "Error: Expected = or array manipulation keyword (APPEND, CLEAR, POP, REMOVE, REMOVEAT)",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },

        .expect_new_value => {
            const data_type = self.schema_engine.memberName2DataType(struct_name, member_name) catch return ZipponError.StructNotFound;
            map.put(
                member_name,
                ValueOrArray{ .value = try self.parseConditionValue(allocator, struct_name, member_name, data_type, &token) },
            ) catch return ZipponError.MemoryError;
            if (data_type == .link or data_type == .link_array) {
                token = self.toker.last_token;
                keep_next = true;
            }
            state = .expect_comma_OR_end;
        },

        .expect_new_array => { // This is what is call after array manipulation keyword
            const member_data_type = self.schema_engine.memberName2DataType(struct_name, member_name) catch return ZipponError.StructNotFound;
            const new_data_type: DataType = switch (token.tag) {
                .l_bracket => switch (member_data_type) {
                    .int, .int_array => .int_array,
                    .float, .float_array => .float_array,
                    .str, .str_array => .str_array,
                    .bool, .bool_array => .bool_array,
                    .date, .date_array => .date_array,
                    .time, .time_array => .time_array,
                    .datetime, .datetime_array => .datetime_array,
                    .link, .link_array => .link_array,
                    else => unreachable,
                },
                .int_literal => switch (member_data_type) {
                    .int, .int_array => .int,
                    else => return printError(
                        "Error, expecting int or int array.",
                        ZipponError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    ),
                },
                .float_literal => switch (member_data_type) {
                    .float, .float_array => .float,
                    else => return printError(
                        "Error, expecting float or float array.",
                        ZipponError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    ),
                },
                .string_literal => switch (member_data_type) {
                    .str, .str_array => .str,
                    else => return printError(
                        "Error, expecting str or str array.",
                        ZipponError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    ),
                },
                .bool_literal_false, .bool_literal_true => switch (member_data_type) {
                    .bool, .bool_array => .bool,
                    else => return printError(
                        "Error, expecting bool or bool array.",
                        ZipponError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    ),
                },
                .date_literal => switch (member_data_type) {
                    .date, .date_array => .date,
                    .datetime, .datetime_array => .datetime,
                    else => return printError(
                        "Error, expecting date or date array.",
                        ZipponError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    ),
                },
                .time_literal => switch (member_data_type) {
                    .time, .time_array => .time,
                    else => return printError(
                        "Error, expecting time or time array.",
                        ZipponError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    ),
                },
                .datetime_literal => switch (member_data_type) {
                    .datetime, .datetime_array => .datetime,
                    else => return printError(
                        "Error, expecting datetime or datetime array.",
                        ZipponError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    ),
                },
                else => return printError(
                    "Error, expecting value or array.",
                    ZipponError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            };
            map.put(
                member_name,
                ValueOrArray{ .array = .{ .condition = .append, .data = try self.parseConditionValue(allocator, struct_name, member_name, new_data_type, &token) } },
            ) catch return ZipponError.MemoryError;
            if (member_data_type == .link or member_data_type == .link_array) {
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
