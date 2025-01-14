const std = @import("std");
const dtype = @import("dtype");
const config = @import("config");
const Allocator = std.mem.Allocator;
const Filter = @import("../../dataStructure/filter.zig").Filter;
const printError = @import("../../utils.zig").printError;

const ZipponError = @import("error").ZipponError;

const Self = @import("../core.zig");

/// Take an array of UUID and populate it with what match what is between {}
/// Main is to know if between {} or (), main is true if between {}, otherwise between () inside {}
pub fn parseFilter(
    self: Self,
    allocator: Allocator,
    struct_name: []const u8,
    is_sub: bool,
) ZipponError!Filter {
    var filter = try Filter.init(allocator);
    errdefer filter.deinit();

    var keep_next = false;
    var token = self.toker.next();
    var state: Self.State = .expect_condition;

    while (state != .end) : ({
        token = if (keep_next) token else self.toker.next();
        keep_next = false;
        if (config.PRINT_STATE) std.debug.print("parseFilter: {any}\n", .{state});
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
                var sub_filter = try parseFilter(self, allocator, struct_name, true);
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
