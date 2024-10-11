const std = @import("std");
const Allocator = std.mem.Allocator;
const DataType = @import("types/dataType.zig").DataType;
const Toker = @import("tokenizers/schema.zig").Tokenizer;
const Token = @import("tokenizers/schema.zig").Token;

const stdout = std.io.getStdOut().writer();

fn send(comptime format: []const u8, args: anytype) void {
    stdout.print(format, args) catch |err| {
        std.log.err("Can't send: {any}", .{err});
        stdout.print("\x03\n", .{}) catch {};
    };

    stdout.print("\x03\n", .{}) catch {};
}

pub const Parser = struct {
    toker: *Toker,
    allocator: Allocator,

    pub fn init(toker: *Toker, allocator: Allocator) Parser {
        return .{
            .allocator = allocator,
            .toker = toker,
        };
    }

    // Maybe I the name and member can be Loc, with a start and end, and use the buffer to get back the value
    // This is how Token works
    // From my understanding this is the same here. I put slices, that can just a len and a pointer, put I con't save the value itself.
    // Or maybe I do actually, and an array of pointer would be *[]u8
    pub const SchemaStruct = struct {
        allocator: Allocator,
        name: Token.Loc,
        members: std.ArrayList(Token.Loc),
        types: std.ArrayList(DataType),

        pub fn init(allocator: Allocator, name: Token.Loc) SchemaStruct {
            return SchemaStruct{ .allocator = allocator, .name = name, .members = std.ArrayList(Token.Loc).init(allocator), .types = std.ArrayList(DataType).init(allocator) };
        }

        pub fn deinit(self: *SchemaStruct) void {
            self.types.deinit();
            self.members.deinit();
        }
    };

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

    // TODO: Pass that to the FileEngine and do the metadata.zig file instead
    pub fn parse(self: *Parser, struct_array: *std.ArrayList(SchemaStruct)) !void {
        var state: State = .expect_struct_name_OR_end;
        var index: usize = 0;
        var keep_next = false;

        var token = self.toker.next();
        while ((state != .end) and (state != .invalid)) : ({
            token = if (!keep_next) self.toker.next() else token;
            keep_next = false;
        }) {
            switch (state) {
                .expect_struct_name_OR_end => switch (token.tag) {
                    .identifier => {
                        state = .expect_l_paren;
                        struct_array.append(SchemaStruct.init(self.allocator, token.loc)) catch @panic("Error appending a struct name.");
                    },
                    .eof => state = .end,
                    else => {
                        self.printError("Error parsing schema: Expected a struct name", &token);
                        state = .invalid;
                    },
                },

                .expect_l_paren => switch (token.tag) {
                    .l_paren => state = .expect_member_name,
                    else => {
                        self.printError("Error parsing schema: Expected (", &token);
                        state = .invalid;
                    },
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
                    else => {
                        self.printError("Error parsing schema: Expected member name or )", &token);
                        state = .invalid;
                    },
                },

                .expect_member_name => {
                    state = .expect_two_dot;
                    struct_array.items[index].members.append(token.loc) catch @panic("Error appending a member name.");
                },

                .expect_two_dot => switch (token.tag) {
                    .two_dot => state = .expect_value_type,
                    else => {
                        self.printError("Error parsing schema: Expected :", &token);
                        state = .invalid;
                    },
                },

                .expect_value_type => switch (token.tag) {
                    .type_int => {
                        state = .expect_comma;
                        struct_array.items[index].types.append(DataType.int) catch @panic("Error appending a type.");
                    },
                    .type_str => {
                        state = .expect_comma;
                        struct_array.items[index].types.append(DataType.str) catch @panic("Error appending a type.");
                    },
                    .type_float => {
                        state = .expect_comma;
                        struct_array.items[index].types.append(DataType.float) catch @panic("Error appending a type.");
                    },
                    .type_bool => {
                        state = .expect_comma;
                        struct_array.items[index].types.append(DataType.bool) catch @panic("Error appending a type.");
                    },
                    .type_date => @panic("Date not yet implemented"),
                    .identifier => @panic("Link not yet implemented"),
                    .lr_bracket => state = .expext_array_type,
                    else => {
                        self.printError("Error parsing schema: Expected data type", &token);
                        state = .invalid;
                    },
                },

                .expext_array_type => switch (token.tag) {
                    .type_int => {
                        state = .expect_comma;
                        struct_array.items[index].types.append(DataType.int_array) catch @panic("Error appending a type.");
                    },
                    .type_str => {
                        state = .expect_comma;
                        struct_array.items[index].types.append(DataType.str_array) catch @panic("Error appending a type.");
                    },
                    .type_float => {
                        state = .expect_comma;
                        struct_array.items[index].types.append(DataType.float_array) catch @panic("Error appending a type.");
                    },
                    .type_bool => {
                        state = .expect_comma;
                        struct_array.items[index].types.append(DataType.bool_array) catch @panic("Error appending a type.");
                    },
                    .type_date => {
                        self.printError("Error parsing schema: Data not yet implemented", &token);
                        state = .invalid;
                    },
                    .identifier => {
                        self.printError("Error parsing schema: Relationship not yet implemented", &token);
                        state = .invalid;
                    },
                    else => {
                        self.printError("Error parsing schema: Expected data type", &token);
                        state = .invalid;
                    },
                },

                .expect_comma => switch (token.tag) {
                    .comma => state = .expect_member_name_OR_r_paren,
                    else => {
                        self.printError("Error parsing schema: Expected ,", &token);
                        state = .invalid;
                    },
                },

                else => unreachable,
            }
        }

        // if invalid, empty the list
        if (state == .invalid) {
            for (0..struct_array.items.len) |i| {
                struct_array.items[i].deinit();
            }

            for (0..struct_array.items.len) |_| {
                _ = struct_array.pop();
            }
            return error.SchemaNotConform;
        }
    }

    fn printError(self: *Parser, message: []const u8, token: *Token) void {
        stdout.print("\n", .{}) catch {};

        const output = self.allocator.dupe(u8, self.toker.buffer) catch @panic("Cant allocator memory when print error");
        defer self.allocator.free(output);

        std.mem.replaceScalar(u8, output, '\n', ' ');
        stdout.print("{s}\n", .{output}) catch {};

        // Calculate the number of spaces needed to reach the start position.
        var spaces: usize = 0;
        while (spaces < token.loc.start) : (spaces += 1) {
            stdout.print(" ", .{}) catch {};
        }

        // Print the '^' characters for the error span.
        var i: usize = token.loc.start;
        while (i < token.loc.end) : (i += 1) {
            stdout.print("^", .{}) catch {};
        }
        stdout.print("    \n", .{}) catch {}; // Align with the message

        stdout.print("{s}\n", .{message}) catch {};

        send("", .{});
    }
};

// TODO: Some test, weird that there isn't any yet
