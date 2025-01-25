const std = @import("std");
const zid = @import("ZipponData");
const SchemaStruct = @import("struct.zig");
const Allocator = std.mem.Allocator;
const DataType = @import("dtype").DataType;
const UUID = @import("dtype").UUID;
const Toker = @import("tokenizer.zig").Tokenizer;
const Token = @import("tokenizer.zig").Token;
const send = @import("../utils.zig").send;
const printError = @import("../utils.zig").printError;

const ZipponError = @import("error").ZipponError;

const State = enum {
    end,
    invalid,
    expect_struct_name_OR_end,
    expect_member_name,
    expect_l_paren,
    expect_member_name_OR_r_paren,
    expect_value_type,
    expext_array_type,
    expect_two_dot,
    expect_comma,
    add_struct,
};

pub const Parser = @This();

toker: *Toker,

pub fn init(toker: *Toker) Parser {
    return .{ .toker = toker };
}

pub fn parse(self: *Parser, allocator: Allocator, struct_array: *std.ArrayList(SchemaStruct)) !void {
    var state: State = .expect_struct_name_OR_end;
    var keep_next = false;

    var member_token: Token = undefined;

    var name: []const u8 = undefined;
    var member_list = std.ArrayList([]const u8).init(allocator);
    defer member_list.deinit();
    var type_list = std.ArrayList(DataType).init(allocator);
    defer type_list.deinit();
    var links = std.StringHashMap([]const u8).init(allocator);
    defer links.deinit();

    var token = self.toker.next();
    while ((state != .end) and (state != .invalid)) : ({
        token = if (!keep_next) self.toker.next() else token;
        keep_next = false;
    }) switch (state) {
        .expect_struct_name_OR_end => switch (token.tag) {
            .identifier => {
                state = .expect_l_paren;
                name = self.toker.getTokenSlice(token);
                member_list.append("id") catch return ZipponError.MemoryError;
                type_list.append(.self) catch return ZipponError.MemoryError;
            },
            .eof => state = .end,
            else => {
                return printError(
                    "Error parsing schema: Expected a struct name",
                    ZipponError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                );
            },
        },

        .expect_l_paren => switch (token.tag) {
            .l_paren => state = .expect_member_name,
            else => return printError(
                "Error parsing schema: Expected (",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },

        .expect_member_name_OR_r_paren => switch (token.tag) {
            .identifier => {
                state = .expect_member_name;
                keep_next = true;
            },
            .r_paren => state = .add_struct,
            else => return printError(
                "Error parsing schema: Expected member name or )",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },

        .add_struct => {
            struct_array.append(try SchemaStruct.init(
                allocator,
                name,
                member_list.toOwnedSlice() catch return ZipponError.MemoryError,
                type_list.toOwnedSlice() catch return ZipponError.MemoryError,
                try links.clone(),
            )) catch return ZipponError.MemoryError;

            links.clearRetainingCapacity();

            member_list = std.ArrayList([]const u8).init(allocator);
            type_list = std.ArrayList(DataType).init(allocator);

            state = .expect_struct_name_OR_end;
            keep_next = true;
        },

        .expect_member_name => {
            state = .expect_two_dot;
            member_list.append(self.toker.getTokenSlice(token)) catch return ZipponError.MemoryError;
            member_token = token;
        },

        .expect_two_dot => switch (token.tag) {
            .two_dot => state = .expect_value_type,
            else => return printError(
                "Error parsing schema: Expected :",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },

        .expect_value_type => switch (token.tag) {
            .type_int => {
                state = .expect_comma;
                type_list.append(.int) catch return ZipponError.MemoryError;
            },
            .type_str => {
                state = .expect_comma;
                type_list.append(.str) catch return ZipponError.MemoryError;
            },
            .type_float => {
                state = .expect_comma;
                type_list.append(.float) catch return ZipponError.MemoryError;
            },
            .type_bool => {
                state = .expect_comma;
                type_list.append(.bool) catch return ZipponError.MemoryError;
            },
            .type_date => {
                state = .expect_comma;
                type_list.append(.date) catch return ZipponError.MemoryError;
            },
            .type_time => {
                state = .expect_comma;
                type_list.append(.time) catch return ZipponError.MemoryError;
            },
            .type_datetime => {
                state = .expect_comma;
                type_list.append(.datetime) catch return ZipponError.MemoryError;
            },
            .identifier => {
                state = .expect_comma;
                type_list.append(.link) catch return ZipponError.MemoryError;
                links.put(self.toker.getTokenSlice(member_token), self.toker.getTokenSlice(token)) catch return ZipponError.MemoryError;
            },
            .lr_bracket => state = .expext_array_type,
            else => return printError(
                "Error parsing schema: Expected data type",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },

        .expext_array_type => switch (token.tag) {
            .type_int => {
                state = .expect_comma;
                type_list.append(.int_array) catch return ZipponError.MemoryError;
            },
            .type_str => {
                state = .expect_comma;
                type_list.append(.str_array) catch return ZipponError.MemoryError;
            },
            .type_float => {
                state = .expect_comma;
                type_list.append(.float_array) catch return ZipponError.MemoryError;
            },
            .type_bool => {
                state = .expect_comma;
                type_list.append(.bool_array) catch return ZipponError.MemoryError;
            },
            .type_date => {
                state = .expect_comma;
                type_list.append(.date_array) catch return ZipponError.MemoryError;
            },
            .type_time => {
                state = .expect_comma;
                type_list.append(.time_array) catch return ZipponError.MemoryError;
            },
            .type_datetime => {
                state = .expect_comma;
                type_list.append(.datetime_array) catch return ZipponError.MemoryError;
            },
            .identifier => {
                state = .expect_comma;
                type_list.append(.link_array) catch return ZipponError.MemoryError;
                links.put(self.toker.getTokenSlice(member_token), self.toker.getTokenSlice(token)) catch return ZipponError.MemoryError;
            },
            else => return printError(
                "Error parsing schema: Expected data type",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },

        .expect_comma => switch (token.tag) {
            .comma => state = .expect_member_name_OR_r_paren,
            else => return printError(
                "Error parsing schema: Expected ,",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },

        else => unreachable,
    };
}
