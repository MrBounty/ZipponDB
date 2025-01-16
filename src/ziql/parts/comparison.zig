const std = @import("std");
const Token = @import("../tokenizer.zig").Token;
const ComparisonOperator = @import("../../dataStructure/filter.zig").ComparisonOperator;
const printError = @import("../../utils.zig").printError;

const ZipponError = @import("error").ZipponError;

const Self = @import("../parser.zig");

pub fn parseComparisonOperator(
    self: Self,
    token: Token,
) ZipponError!ComparisonOperator {
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
