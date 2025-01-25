const std = @import("std");
const config = @import("config");
const Allocator = std.mem.Allocator;
const Token = @import("../tokenizer.zig").Token;
const Condition = @import("../../dataStructure/filter.zig").Condition;
const printError = @import("../../utils.zig").printError;
const log = std.log.scoped(.ziqlParser);

const ZipponError = @import("error").ZipponError;

const Self = @import("../parser.zig");

/// Parse to get a Condition. Which is a struct that is use by the FileEngine to retreive data.
/// In the query, it is this part name = 'Bob' or age <= 10
pub fn parseCondition(
    self: Self,
    allocator: Allocator,
    token_ptr: *Token,
    struct_name: []const u8,
) ZipponError!Condition {
    var keep_next = false;
    var state: Self.State = .expect_member;
    var token = token_ptr.*;
    var member_name: []const u8 = undefined;

    var condition = Condition{};

    while (state != .end) : ({
        token = if (!keep_next) self.toker.next() else token;
        keep_next = false;
        if (config.PRINT_STATE) std.debug.print("parseCondition: {any}\n", .{state});
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
            if (condition.operation == .in) condition.data_type = switch (condition.data_type) {
                .int => .int_array,
                .float => .float_array,
                .str => .str_array,
                .bool => .bool_array,
                .date => .date_array,
                .time => .time_array,
                .datetime => .datetime_array,
                else => condition.data_type,
            };
            log.debug("Condition operation {any}\n", .{condition.operation});
            state = .expect_value;
        },

        .expect_value => {
            condition.value = try self.parseConditionValue(allocator, struct_name, member_name, condition.data_type, &token);
            state = .end;
        },

        else => unreachable,
    };

    try self.checkConditionValidity(condition, token);

    return condition;
}

pub fn checkConditionValidity(
    self: Self,
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
            .link, .int_array, .float_array, .str_array, .bool_array, .time_array, .date_array, .datetime_array => {},
            else => unreachable,
        },

        .not_in => switch (condition.data_type) {
            .link, .int_array, .float_array, .str_array, .bool_array, .time_array, .date_array, .datetime_array => {},
            else => unreachable,
        },
    }
}
