const std = @import("std");
const Allocator = std.mem.Allocator;
const DataType = @import("types/dataType.zig").DataType;
const Toker = @import("tokenizers/schema.zig").Tokenizer;
const Token = @import("tokenizers/schema.zig").Token;
const Loc = @import("tokenizers/shared/loc.zig").Loc;
const send = @import("stuffs/utils.zig").send;
const printError = @import("stuffs/utils.zig").printError;

const SchemaParserError = @import("stuffs/errors.zig").SchemaParserError;

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
};

pub const Parser = struct {
    toker: *Toker,
    allocator: Allocator,

    pub fn init(toker: *Toker, allocator: Allocator) Parser {
        return .{
            .allocator = allocator,
            .toker = toker,
        };
    }

    pub const SchemaStruct = struct {
        allocator: Allocator,
        name: []const u8,
        members: std.ArrayList([]const u8),
        types: std.ArrayList(DataType),
        links: std.StringHashMap([]const u8),

        pub fn init(allocator: Allocator, name: []const u8) SchemaStruct {
            return SchemaStruct{
                .allocator = allocator,
                .name = name,
                .members = std.ArrayList([]const u8).init(allocator),
                .types = std.ArrayList(DataType).init(allocator),
                .links = std.StringHashMap([]const u8).init(allocator),
            };
        }

        pub fn deinit(self: *SchemaStruct) void {
            self.types.deinit();
            self.members.deinit();
            self.links.deinit();
        }
    };

    pub fn parse(self: *Parser, struct_array: *std.ArrayList(SchemaStruct)) !void {
        var state: State = .expect_struct_name_OR_end;
        var index: usize = 0;
        var keep_next = false;

        errdefer {
            for (0..struct_array.items.len) |i| {
                struct_array.items[i].deinit();
            }

            for (0..struct_array.items.len) |_| {
                _ = struct_array.pop();
            }
        }

        var member_token: Token = undefined;

        var token = self.toker.next();
        while ((state != .end) and (state != .invalid)) : ({
            token = if (!keep_next) self.toker.next() else token;
            keep_next = false;
        }) switch (state) {
            .expect_struct_name_OR_end => switch (token.tag) {
                .identifier => {
                    state = .expect_l_paren;
                    struct_array.append(SchemaStruct.init(self.allocator, self.toker.getTokenSlice(token))) catch return SchemaParserError.MemoryError;
                },
                .eof => state = .end,
                else => return printError(
                    "Error parsing schema: Expected a struct name",
                    SchemaParserError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },

            .expect_l_paren => switch (token.tag) {
                .l_paren => state = .expect_member_name,
                else => return printError(
                    "Error parsing schema: Expected (",
                    SchemaParserError.SynthaxError,
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
                .r_paren => {
                    state = .expect_struct_name_OR_end;
                    index += 1;
                },
                else => return printError(
                    "Error parsing schema: Expected member name or )",
                    SchemaParserError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },

            .expect_member_name => {
                state = .expect_two_dot;
                struct_array.items[index].members.append(self.toker.getTokenSlice(token)) catch return SchemaParserError.MemoryError;
                member_token = token;
            },

            .expect_two_dot => switch (token.tag) {
                .two_dot => state = .expect_value_type,
                else => return printError(
                    "Error parsing schema: Expected :",
                    SchemaParserError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },

            .expect_value_type => switch (token.tag) {
                .type_int => {
                    state = .expect_comma;
                    struct_array.items[index].types.append(.int) catch return SchemaParserError.MemoryError;
                },
                .type_str => {
                    state = .expect_comma;
                    struct_array.items[index].types.append(.str) catch return SchemaParserError.MemoryError;
                },
                .type_float => {
                    state = .expect_comma;
                    struct_array.items[index].types.append(.float) catch return SchemaParserError.MemoryError;
                },
                .type_bool => {
                    state = .expect_comma;
                    struct_array.items[index].types.append(.bool) catch return SchemaParserError.MemoryError;
                },
                .type_date => {
                    state = .expect_comma;
                    struct_array.items[index].types.append(.date) catch return SchemaParserError.MemoryError;
                },
                .type_time => {
                    state = .expect_comma;
                    struct_array.items[index].types.append(.time) catch return SchemaParserError.MemoryError;
                },
                .type_datetime => {
                    state = .expect_comma;
                    struct_array.items[index].types.append(.datetime) catch return SchemaParserError.MemoryError;
                },
                .identifier => {
                    state = .expect_comma;
                    struct_array.items[index].types.append(.link) catch return SchemaParserError.MemoryError;
                    struct_array.items[index].links.put(self.toker.getTokenSlice(member_token), self.toker.getTokenSlice(token)) catch return SchemaParserError.MemoryError;
                },
                .lr_bracket => state = .expext_array_type,
                else => return printError(
                    "Error parsing schema: Expected data type",
                    SchemaParserError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },

            .expext_array_type => switch (token.tag) {
                .type_int => {
                    state = .expect_comma;
                    struct_array.items[index].types.append(DataType.int_array) catch return SchemaParserError.MemoryError;
                },
                .type_str => {
                    state = .expect_comma;
                    struct_array.items[index].types.append(DataType.str_array) catch return SchemaParserError.MemoryError;
                },
                .type_float => {
                    state = .expect_comma;
                    struct_array.items[index].types.append(DataType.float_array) catch return SchemaParserError.MemoryError;
                },
                .type_bool => {
                    state = .expect_comma;
                    struct_array.items[index].types.append(DataType.bool_array) catch return SchemaParserError.MemoryError;
                },
                .type_date => {
                    state = .expect_comma;
                    struct_array.items[index].types.append(DataType.date_array) catch return SchemaParserError.MemoryError;
                },
                .type_time => {
                    state = .expect_comma;
                    struct_array.items[index].types.append(DataType.time_array) catch return SchemaParserError.MemoryError;
                },
                .type_datetime => {
                    state = .expect_comma;
                    struct_array.items[index].types.append(DataType.datetime_array) catch return SchemaParserError.MemoryError;
                },
                .identifier => {
                    state = .expect_comma;
                    struct_array.items[index].types.append(.link) catch return SchemaParserError.MemoryError;
                    struct_array.items[index].links.put(self.toker.getTokenSlice(member_token), self.toker.getTokenSlice(token)) catch return SchemaParserError.MemoryError;
                },
                else => return printError(
                    "Error parsing schema: Expected data type",
                    SchemaParserError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },

            .expect_comma => switch (token.tag) {
                .comma => state = .expect_member_name_OR_r_paren,
                else => return printError(
                    "Error parsing schema: Expected ,",
                    SchemaParserError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },

            else => unreachable,
        };
    }
};

// TODO: Some test, weird that there isn't any yet
