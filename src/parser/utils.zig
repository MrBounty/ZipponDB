const std = @import("std");
const config = @import("config");
const Allocator = std.mem.Allocator;
const Token = @import("tokenizer.zig").Token;
const Condition = @import("../dataStructure/filter.zig").Condition;
const printError = @import("../utils.zig").printError;

const ZipponError = @import("error").ZipponError;

const Self = @import("core.zig");

/// Check if all token in an array is of one specific type
pub fn checkTokensInArray(self: Self, tag: Token.Tag) ZipponError!Token {
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

/// Will check if what is compared is ok, like comparing if a string is superior to another string is not for example.
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
