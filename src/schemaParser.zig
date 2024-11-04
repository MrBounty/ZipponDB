const std = @import("std");
const zid = @import("ZipponData");
const Allocator = std.mem.Allocator;
const DataType = @import("dtype").DataType;
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
    add_struct,
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

    // Rename something better and move it somewhere else
    pub const SchemaStruct = struct {
        allocator: Allocator,
        name: []const u8,
        members: [][]const u8,
        types: []DataType,
        zid_schema: []zid.DType,
        links: std.StringHashMap([]const u8), // Map key as member_name and value as struct_name, like a dtype
        // uuid_file_index: std.AutoHashMap([16]u8, u64), // Map UUID to the index of the file they are store in

        pub fn init(
            allocator: Allocator,
            name: []const u8,
            members: [][]const u8,
            types: []DataType,
            links: std.StringHashMap([]const u8),
        ) SchemaParserError!SchemaStruct {
            return SchemaStruct{
                .allocator = allocator,
                .name = name,
                .members = members,
                .types = types,
                .zid_schema = SchemaStruct.fileDataSchema(allocator, types) catch return SchemaParserError.MemoryError,
                .links = links,
                //.uuid_file_index = std.AutoHashMap([16]u8, u64).init(allocator),
            };
        }

        pub fn deinit(self: *SchemaStruct) void {
            self.allocator.free(self.members);
            self.allocator.free(self.types);
            self.allocator.free(self.zid_schema);
            self.links.deinit();
            //self.uuid_file_index.deinit();
        }

        fn fileDataSchema(allocator: Allocator, dtypes: []DataType) SchemaParserError![]zid.DType {
            var schema = std.ArrayList(zid.DType).init(allocator);

            for (dtypes) |dt| {
                schema.append(switch (dt) {
                    .int => .Int,
                    .float => .Float,
                    .str => .Str,
                    .bool => .Bool,
                    .link, .self => .UUID,
                    .date => .Unix,
                    .time => .Unix,
                    .datetime => .Unix,
                    .int_array => .IntArray,
                    .float_array => .FloatArray,
                    .str_array => .StrArray,
                    .bool_array => .BoolArray,
                    .link_array => .UUIDArray,
                    .date_array => .UnixArray,
                    .time_array => .UnixArray,
                    .datetime_array => .UnixArray,
                }) catch return SchemaParserError.MemoryError;
            }
            return schema.toOwnedSlice() catch return SchemaParserError.MemoryError;
        }
    };

    pub fn parse(self: *Parser, struct_array: *std.ArrayList(SchemaStruct)) !void {
        var state: State = .expect_struct_name_OR_end;
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

        var name: []const u8 = undefined;
        var member_list = std.ArrayList([]const u8).init(self.allocator);
        defer member_list.deinit();
        var type_list = std.ArrayList(DataType).init(self.allocator);
        defer type_list.deinit();
        var links = std.StringHashMap([]const u8).init(self.allocator);
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
                    member_list.append("id") catch return SchemaParserError.MemoryError;
                    type_list.append(.self) catch return SchemaParserError.MemoryError;
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
                .r_paren => state = .add_struct,
                else => return printError(
                    "Error parsing schema: Expected member name or )",
                    SchemaParserError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            },

            .add_struct => {
                struct_array.append(try SchemaStruct.init(
                    self.allocator,
                    name,
                    member_list.toOwnedSlice() catch return SchemaParserError.MemoryError,
                    type_list.toOwnedSlice() catch return SchemaParserError.MemoryError,
                    try links.clone(),
                )) catch return SchemaParserError.MemoryError;

                links.deinit();
                links = std.StringHashMap([]const u8).init(self.allocator);

                member_list = std.ArrayList([]const u8).init(self.allocator);
                type_list = std.ArrayList(DataType).init(self.allocator);

                state = .expect_struct_name_OR_end;
            },

            .expect_member_name => {
                state = .expect_two_dot;
                member_list.append(self.toker.getTokenSlice(token)) catch return SchemaParserError.MemoryError;
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
                    type_list.append(.int) catch return SchemaParserError.MemoryError;
                },
                .type_str => {
                    state = .expect_comma;
                    type_list.append(.str) catch return SchemaParserError.MemoryError;
                },
                .type_float => {
                    state = .expect_comma;
                    type_list.append(.float) catch return SchemaParserError.MemoryError;
                },
                .type_bool => {
                    state = .expect_comma;
                    type_list.append(.bool) catch return SchemaParserError.MemoryError;
                },
                .type_date => {
                    state = .expect_comma;
                    type_list.append(.date) catch return SchemaParserError.MemoryError;
                },
                .type_time => {
                    state = .expect_comma;
                    type_list.append(.time) catch return SchemaParserError.MemoryError;
                },
                .type_datetime => {
                    state = .expect_comma;
                    type_list.append(.datetime) catch return SchemaParserError.MemoryError;
                },
                .identifier => {
                    state = .expect_comma;
                    type_list.append(.link) catch return SchemaParserError.MemoryError;
                    links.put(self.toker.getTokenSlice(member_token), self.toker.getTokenSlice(token)) catch return SchemaParserError.MemoryError;
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
                    type_list.append(.int_array) catch return SchemaParserError.MemoryError;
                },
                .type_str => {
                    state = .expect_comma;
                    type_list.append(.str_array) catch return SchemaParserError.MemoryError;
                },
                .type_float => {
                    state = .expect_comma;
                    type_list.append(.float_array) catch return SchemaParserError.MemoryError;
                },
                .type_bool => {
                    state = .expect_comma;
                    type_list.append(.bool_array) catch return SchemaParserError.MemoryError;
                },
                .type_date => {
                    state = .expect_comma;
                    type_list.append(.date_array) catch return SchemaParserError.MemoryError;
                },
                .type_time => {
                    state = .expect_comma;
                    type_list.append(.time_array) catch return SchemaParserError.MemoryError;
                },
                .type_datetime => {
                    state = .expect_comma;
                    type_list.append(.datetime_array) catch return SchemaParserError.MemoryError;
                },
                .identifier => {
                    state = .expect_comma;
                    type_list.append(.link_array) catch return SchemaParserError.MemoryError;
                    links.put(self.toker.getTokenSlice(member_token), self.toker.getTokenSlice(token)) catch return SchemaParserError.MemoryError;
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
