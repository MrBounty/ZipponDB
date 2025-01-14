const std = @import("std");
const config = @import("config");
const Allocator = std.mem.Allocator;
const Token = @import("../tokenizer.zig").Token;
const AdditionalData = @import("../../dataStructure/additionalData.zig").AdditionalData;
const printError = @import("../../utils.zig").printError;

const ZipponError = @import("error").ZipponError;

const Self = @import("../core.zig");

/// When this function is call, next token should be [
/// Check if an int is here -> check if ; is here -> check if member is here -> check if [ is here -> loop
pub fn parseAdditionalData(
    self: Self,
    allocator: Allocator,
    additional_data: *AdditionalData,
    struct_name: []const u8,
) ZipponError!void {
    var token = self.toker.next();
    var keep_next = false;
    var state: Self.State = .expect_limit;
    var last_member: []const u8 = undefined;

    while (state != .end) : ({
        token = if ((!keep_next) and (state != .end)) self.toker.next() else token;
        keep_next = false;
        if (config.PRINT_STATE) std.debug.print("parseAdditionalData: {any}\n", .{state});
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
                try parseAdditionalData(
                    self,
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
