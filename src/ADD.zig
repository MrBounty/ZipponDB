const std = @import("std");
const dtypes = @import("dtypes.zig");
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
    arena: std.heap.ArenaAllocator,
    allocator: Allocator,

    toker: *Tokenizer,
    data_engine: *DataEngine,

    pub fn init(allocator: Allocator, toker: *Tokenizer, data_engine: *DataEngine) Parser {
        var arena = std.heap.ArenaAllocator.init(allocator);
        return Parser{
            .arena = arena,
            .allocator = arena.allocator(),
            .toker = toker,
            .data_engine = data_engine,
        };
    }

    pub fn deinit(self: *Parser) void {
        self.arena.deinit();
    }

    pub fn parse(self: *Parser, struct_name: []const u8) !void {
        var token = self.toker.next();
        switch (token.tag) {
            .l_paren => {},
            else => {
                try self.print_error("Error: Expected (", &token);
            },
        }

        const buffer = try self.allocator.alloc(u8, 1024 * 100);
        defer self.allocator.free(buffer);

        var data = self.parseData(); // data is a map with key as member name and value as str of the value inserted in the query. So age = 12 is the string 12 here
        defer data.deinit();

        if (!self.checkIfAllMemberInMap(struct_name, &data)) return;

        const entity = try dtypes.createEntityFromMap(self.allocator, struct_name, data);
        const uuid_str = entity.User.*.id.format_uuid();
        defer stdout.print("Added new {s} successfully using UUID: {s}\n", .{
            struct_name,
            uuid_str,
        }) catch {};

        const member_names = dtypes.structName2structMembers(struct_name);
        for (member_names) |member_name| {
            var file_map = self.data_engine.getFilesStat(struct_name, member_name) catch {
                try stdout.print("Error: File stat error", .{});
                return;
            };
            const potential_file_name_to_use = self.data_engine.getFirstUsableFile(file_map);
            if (potential_file_name_to_use) |file_name| {
                const file_index = self.data_engine.fileName2Index(file_name);
                try stdout.print("Using file: {s} with a size of {d}\n", .{ file_name, file_map.get(file_name).?.size });

                const path = try std.fmt.bufPrint(buffer, "ZipponDB/DATA/{s}/{s}/{s}", .{
                    struct_name,
                    member_name,
                    file_name,
                });

                var file = std.fs.cwd().openFile(path, .{
                    .mode = .read_write,
                }) catch {
                    try stdout.print("Error opening data file.", .{});
                    return;
                };
                defer file.close();

                try file.seekFromEnd(0);
                try file.writer().print("{s} {s}\n", .{ uuid_str, data.get(member_name).? });

                const path_to_main = try std.fmt.bufPrint(buffer, "ZipponDB/DATA/{s}/{s}/main.zippondata", .{
                    struct_name,
                    member_name,
                });

                var file_main = std.fs.cwd().openFile(path_to_main, .{
                    .mode = .read_write,
                }) catch {
                    try stdout.print("Error opening data file.", .{});
                    return;
                };
                defer file_main.close();

                try self.data_engine.appendToLineAtIndex(file_main, file_index, &uuid_str);
            } else {
                const max_index = self.data_engine.maxFileIndex(file_map);

                const new_file_path = try std.fmt.bufPrint(buffer, "ZipponDB/DATA/{s}/{s}/{d}.zippondata", .{
                    struct_name,
                    member_name,
                    max_index + 1,
                });

                try stdout.print("new file path: {s}\n", .{new_file_path});

                // TODO: Create new file and save the data inside
                const new_file = std.fs.cwd().createFile(new_file_path, .{}) catch @panic("Error creating new data file");
                defer new_file.close();

                try new_file.writer().print("{s} {s}\n", .{ &uuid_str, data.get(member_name).? });

                const path_to_main = try std.fmt.bufPrint(buffer, "ZipponDB/DATA/{s}/{s}/main.zippondata", .{
                    struct_name,
                    member_name,
                });

                var file_main = std.fs.cwd().openFile(path_to_main, .{
                    .mode = .read_write,
                }) catch {
                    try stdout.print("Error opening data file.", .{});
                    @panic("");
                };
                defer file_main.close();

                try file_main.seekFromEnd(0);
                try file_main.writeAll("\n ");
                try file_main.seekTo(0);
                try self.data_engine.appendToLineAtIndex(file_main, max_index + 1, &uuid_str);
            }
        }
    }

    /// Take the tokenizer and return a map of the query for the ADD command.
    /// Keys are the member name and value are the string of the value in the query. E.g. 'Adrien' or '10'
    pub fn parseData(self: *Parser) std.StringHashMap([]const u8) {
        var token = self.toker.next();

        var member_map = std.StringHashMap([]const u8).init(
            self.allocator,
        );

        while (token.tag != Token.Tag.eof) : (token = self.toker.next()) {
            switch (token.tag) {
                .r_paren => continue,
                .identifier => {
                    const member_name_str = self.toker.getTokenSlice(token);
                    token = self.toker.next();
                    switch (token.tag) {
                        .equal => {
                            token = self.toker.next();
                            switch (token.tag) {
                                .string_literal, .number_literal => {
                                    const value_str = self.toker.getTokenSlice(token);
                                    member_map.put(member_name_str, value_str) catch @panic("Could not add member name and value to map in getMapOfMember");
                                    token = self.toker.next();
                                    switch (token.tag) {
                                        .comma, .r_paren => continue,
                                        else => self.print_error("Error: Expected , after string or number. E.g. ADD User (name='bob', age=10)", &token) catch {},
                                    }
                                },
                                .keyword_null => {
                                    const value_str = "null";
                                    member_map.put(member_name_str, value_str) catch self.print_error("Error: 001", &token) catch {};
                                    token = self.toker.next();
                                    switch (token.tag) {
                                        .comma, .r_paren => continue,
                                        else => self.print_error("Error: Expected , after string or number. E.g. ADD User (name='bob', age=10)", &token) catch {},
                                    }
                                },
                                .l_bracket => {
                                    var array_values = std.ArrayList([]const u8).init(self.allocator);
                                    token = self.toker.next();
                                    while (token.tag != Token.Tag.r_bracket) : (token = self.toker.next()) {
                                        switch (token.tag) {
                                            .string_literal, .number_literal => {
                                                const value_str = self.toker.getTokenSlice(token);
                                                array_values.append(value_str) catch @panic("Could not add value to array in getMapOfMember");
                                            },
                                            else => self.print_error("Error: Expected string or number in array. E.g. ADD User (scores=[10 20 30])", &token) catch {},
                                        }
                                    }
                                    // Maybe change that as it just recreate a string that is already in the buffer
                                    const array_str = std.mem.join(self.allocator, " ", array_values.items) catch @panic("Couln't join the value of array");
                                    member_map.put(member_name_str, array_str) catch @panic("Could not add member name and value to map in getMapOfMember");
                                },
                                else => self.print_error("Error: Expected string or number after =. E.g. ADD User (name='bob')", &token) catch {},
                            }
                        },
                        else => self.print_error("Error: Expected = after a member declaration. E.g. ADD User (name='bob')", &token) catch {},
                    }
                },
                else => self.print_error("Error: Unknow token. This should be the name of a member. E.g. name in ADD User (name='bob')", &token) catch {},
            }
        }

        return member_map;
    }

    fn checkIfAllMemberInMap(_: *Parser, struct_name: []const u8, map: *std.StringHashMap([]const u8)) bool {
        const all_struct_member = dtypes.structName2structMembers(struct_name);
        var count: u16 = 0;

        for (all_struct_member) |key| {
            if (map.contains(key)) count += 1 else stdout.print("Error: ADD query of struct: {s}; missing member: {s}\n", .{
                struct_name,
                key,
            }) catch {};
        }

        return ((count == all_struct_member.len) and (count == map.count()));
    }

    fn print_error(self: *Parser, message: []const u8, token: *Token) !void {
        try stdout.print("\n", .{});
        try stdout.print("{s}\n", .{self.toker.buffer});

        // Calculate the number of spaces needed to reach the start position.
        var spaces: usize = 0;
        while (spaces < token.loc.start) : (spaces += 1) {
            try stdout.print(" ", .{});
        }

        // Print the '^' characters for the error span.
        var i: usize = token.loc.start;
        while (i < token.loc.end) : (i += 1) {
            try stdout.print("^", .{});
        }
        try stdout.print("    \n", .{}); // Align with the message

        try stdout.print("{s}\n", .{message});

        @panic("");
    }
};
