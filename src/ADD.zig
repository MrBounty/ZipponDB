const std = @import("std");
const metadata = @import("metadata.zig");
const UUID = @import("uuid.zig").UUID;
const Tokenizer = @import("ziqlTokenizer.zig").Tokenizer;
const Token = @import("ziqlTokenizer.zig").Token;
const DataEngine = @import("dataEngine.zig").DataEngine;
const Allocator = std.mem.Allocator;

const stdout = std.io.getStdOut().writer();

// Query that need to work now
// ADD User (name='Adrien', email='adrien.bouvais@gmail.com')                                   OK
// ADD User (name='Adrien', email='adrien.bouvais@gmail.com', age = 26)                         OK
// ADD User (name='Adrien', email='adrien.bouvais@gmail.com', books = ['book1', 'book2'])       OK
// ADD User (name='Adrien', email=null)                                                         OK
//
// For later: links
// ADD User (name = 'Adrien', best_friend = {name='bob'}, friends = {name != 'bob'})            NOT OK
// ADD User (name = 'Adrien', friends = {(name = 'bob' AND age > 16) OR (id = '0000-0000')} )   NOT OK
// TODO: make real test

/// Function for the ADD query command.
/// It will parse the reste of the query and create a map of member name / value.
/// Then add those value to the appropriete file. The proper file is the first one with a size < to the limit.
/// If no file is found, a new one is created.
/// Take the main.zippondata file, the index of the file where the data is saved and the string to add at the end of the line
pub const Parser = struct {
    allocator: Allocator,
    toker: *Tokenizer,

    pub fn init(allocator: Allocator, toker: *Tokenizer) Parser {
        return Parser{
            .allocator = allocator,
            .toker = toker,
        };
    }

    pub fn parse(self: *Parser) !void {
        var data_engine = DataEngine.init(self.allocator, null);
        defer data_engine.deinit();

        var struct_name_token = self.toker.next();
        const struct_name = self.toker.getTokenSlice(struct_name_token);

        if (!metadata.isStructNameExists(struct_name)) self.print_error("Struct not found in current schema", &struct_name_token);

        var token = self.toker.next();
        switch (token.tag) {
            .l_paren => {},
            else => {
                self.print_error("Error: Expected (", &token);
            },
        }

        var data_map = self.parseData(struct_name);
        defer data_map.deinit();

        if (self.checkIfAllMemberInMap(struct_name, &data_map)) {
            try data_engine.writeEntity(struct_name, data_map);
        } else |_| {}
    }

    /// Take the tokenizer and return a map of the query for the ADD command.
    /// Keys are the member name and value are the string of the value in the query. E.g. 'Adrien' or '10'
    /// TODO: Make it clean using a State like other parser
    pub fn parseData(self: *Parser, struct_name: []const u8) std.StringHashMap([]const u8) {
        var token = self.toker.next();

        var member_map = std.StringHashMap([]const u8).init(self.allocator);

        while (token.tag != Token.Tag.eof) : (token = self.toker.next()) {
            switch (token.tag) {
                .r_paren => continue,
                .identifier => {
                    const member_name_str = self.toker.getTokenSlice(token);

                    if (!metadata.isMemberNameInStruct(struct_name, member_name_str)) self.print_error("Member not found in struct.", &token);
                    token = self.toker.next();
                    switch (token.tag) {
                        .equal => {
                            token = self.toker.next();
                            switch (token.tag) {
                                .string_literal, .number_literal => {
                                    const value_str = self.toker.getTokenSlice(token);
                                    member_map.put(member_name_str, value_str) catch self.print_error("Could not add member name and value to map in getMapOfMember", &token);
                                    token = self.toker.next();
                                    switch (token.tag) {
                                        .comma, .r_paren => continue,
                                        else => self.print_error("Error: Expected , after string or number. E.g. ADD User (name='bob', age=10)", &token),
                                    }
                                },
                                .keyword_null => {
                                    const value_str = "null";
                                    member_map.put(member_name_str, value_str) catch self.print_error("Error: 001", &token);
                                    token = self.toker.next();
                                    switch (token.tag) {
                                        .comma, .r_paren => continue,
                                        else => self.print_error("Error: Expected , after string or number. E.g. ADD User (name='bob', age=10)", &token),
                                    }
                                },
                                // Create a tag to prevent creating an array then join them. Instead just read the buffer from [ to ] in the tekenizer itself
                                .l_bracket => {
                                    var array_values = std.ArrayList([]const u8).init(self.allocator);
                                    token = self.toker.next();
                                    while (token.tag != Token.Tag.r_bracket) : (token = self.toker.next()) {
                                        switch (token.tag) {
                                            .string_literal, .number_literal => {
                                                const value_str = self.toker.getTokenSlice(token);
                                                array_values.append(value_str) catch self.print_error("Could not add value to array in getMapOfMember", &token);
                                            },
                                            else => self.print_error("Error: Expected string or number in array. E.g. ADD User (scores=[10 20 30])", &token),
                                        }
                                    }
                                    // Maybe change that as it just recreate a string that is already in the buffer
                                    const array_str = std.mem.join(self.allocator, " ", array_values.items) catch {
                                        self.print_error("Couln't join the value of array", &token);
                                        @panic("=)");
                                    };
                                    member_map.put(member_name_str, array_str) catch self.print_error("Could not add member name and value to map in getMapOfMember", &token);

                                    token = self.toker.next();
                                    switch (token.tag) {
                                        .comma, .r_paren => continue,
                                        else => self.print_error("Error: Expected , after string or number. E.g. ADD User (name='bob', age=10)", &token),
                                    }
                                },
                                else => self.print_error("Error: Expected string or number after =. E.g. ADD User (name='bob')", &token),
                            }
                        },
                        else => self.print_error("Error: Expected = after a member declaration. E.g. ADD User (name='bob')", &token),
                    }
                },
                else => self.print_error("Error: Unknow token. This should be the name of a member. E.g. name in ADD User (name='bob')", &token),
            }
        }

        return member_map;
    }

    const AddError = error{NotAllMemberInMap};

    fn checkIfAllMemberInMap(_: *Parser, struct_name: []const u8, map: *std.StringHashMap([]const u8)) !void {
        const all_struct_member = metadata.structName2structMembers(struct_name);
        var count: u16 = 0;
        var started_printing = false;

        for (all_struct_member) |key| {
            if (map.contains(key)) count += 1 else {
                if (!started_printing) {
                    try stdout.print("Error: ADD query of struct: {s}; missing member: {s}", .{ struct_name, key });
                    started_printing = true;
                } else {
                    try stdout.print(" {s}", .{key});
                }
            }
        }

        if (started_printing) try stdout.print("\n", .{});

        if (!((count == all_struct_member.len) and (count == map.count()))) return error.NotAllMemberInMap;
    }

    fn print_error(self: *Parser, message: []const u8, token: *Token) void {
        stdout.print("\n", .{}) catch {};
        stdout.print("{s}\n", .{self.toker.buffer}) catch {};

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

        @panic("");
    }
};
