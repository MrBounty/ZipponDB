const std = @import("std");
const config = @import("config");
const Allocator = std.mem.Allocator;
const ConditionValue = @import("../../dataStructure/filter.zig").ConditionValue;
const printError = @import("../../utils.zig").printError;

const ZipponError = @import("error").ZipponError;

const Self = @import("../parser.zig");

/// Take the tokenizer and return a map of the ADD action.
/// Keys are the member name and value are the string of the value in the query. E.g. 'Adrien' or '10'
/// Entry token need to be (
pub fn parseNewData(
    self: Self,
    allocator: Allocator,
    map: *std.StringHashMap(ConditionValue),
    struct_name: []const u8,
    order: *std.ArrayList([]const u8),
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
