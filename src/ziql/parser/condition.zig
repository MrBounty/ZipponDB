const std = @import("std");
const config = @import("config");
const Allocator = std.mem.Allocator;
const Token = @import("../tokenizer.zig").Token;
const Condition = @import("../../dataStructure/filter.zig").Condition;
const printError = @import("../../utils.zig").printError;
const log = std.log.scoped(.ziqlParser);

const ZipponError = @import("error").ZipponError;

const Self = @import("../core.zig");

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
