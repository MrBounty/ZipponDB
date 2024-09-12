const std = @import("std");
const dtypes = @import("../dtypes.zig");
const UUID = @import("../uuid.zig").UUID;
const ziqlTokenizer = @import("../tokenizers/ziqlTokenizer.zig").Tokenizer;
const ziqlToken = @import("../tokenizers/ziqlTokenizer.zig").Token;
const Allocator = std.mem.Allocator;

const stdout = std.io.getStdOut().writer();

// TODO to improve this part of the code:
// 1. Use logging
// 2. Create a struct that manage files with member: stdout, folder (e.g. the User folder),

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
pub fn parseDataAndAddToFile(allocator: Allocator, struct_name: []const u8, toker: *ziqlTokenizer) !void {
    const token = toker.next();
    switch (token.tag) {
        .l_paren => {},
        else => {
            try stdout.print("Error: Expected ( after the struct name of an ADD command.\nE.g. ADD User (name = 'bob')\n", .{});
            return;
        },
    }

    const buffer = try allocator.alloc(u8, 1024 * 100);
    defer allocator.free(buffer);

    var member_map = getMapOfMember(allocator, toker) catch return;
    defer member_map.deinit();

    if (!checkIfAllMemberInMap(struct_name, &member_map)) return;

    const entity = try dtypes.createEntityFromMap(allocator, struct_name, member_map);
    const uuid_str = entity.User.*.id.format_uuid();
    defer stdout.print("Added new {s} successfully using UUID: {s}\n", .{
        struct_name,
        uuid_str,
    }) catch {};

    const member_names = dtypes.structName2structMembers(struct_name);
    for (member_names) |member_name| {
        var file_map = getFilesStat(allocator, struct_name, member_name) catch {
            try stdout.print("Error: File stat error", .{});
            return;
        };
        const potential_file_name_to_use = getFirstUsableFile(file_map);
        if (potential_file_name_to_use) |file_name| {
            const file_index = fileName2Index(file_name) catch @panic("Error in fileName2Index");
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
            try file.writer().print("{s} {s}\n", .{ uuid_str, member_map.get(member_name).? });

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

            try appendToLineAtIndex(allocator, file_main, file_index, &uuid_str);
        } else {
            const max_index = maxFileIndex(file_map);

            const new_file_path = try std.fmt.bufPrint(buffer, "ZipponDB/DATA/{s}/{s}/{d}.zippondata", .{
                struct_name,
                member_name,
                max_index + 1,
            });

            try stdout.print("new file path: {s}\n", .{new_file_path});

            // TODO: Create new file and save the data inside
            const new_file = std.fs.cwd().createFile(new_file_path, .{}) catch @panic("Error creating new data file");
            defer new_file.close();

            try new_file.writer().print("{s} {s}\n", .{ &uuid_str, member_map.get(member_name).? });

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
            try appendToLineAtIndex(allocator, file_main, max_index + 1, &uuid_str);
        }
    }
}

/// Take the main.zippondata file, the index of the file where the data is saved and the string to add at the end of the line
fn appendToLineAtIndex(allocator: std.mem.Allocator, file: std.fs.File, index: usize, str: []const u8) !void {
    const buffer = try allocator.alloc(u8, 1024 * 100);
    defer allocator.free(buffer);

    var reader = file.reader();

    var line_num: usize = 1;
    while (try reader.readUntilDelimiterOrEof(buffer, '\n')) |_| {
        if (line_num == index) {
            try file.seekBy(-1);
            try file.writer().print("{s}  ", .{str});
            return;
        }
        line_num += 1;
    }
}

/// Return a map of file path => Stat for one struct and member name
fn getFilesStat(allocator: Allocator, struct_name: []const u8, member_name: []const u8) !*std.StringHashMap(std.fs.File.Stat) {
    const cwd = std.fs.cwd();

    const buffer = try allocator.alloc(u8, 1024); // Adjust the size as needed
    defer allocator.free(buffer);

    const path = try std.fmt.bufPrint(buffer, "ZipponDB/DATA/{s}/{s}", .{ struct_name, member_name });

    var file_map = std.StringHashMap(std.fs.File.Stat).init(allocator);

    const member_dir = cwd.openDir(path, .{ .iterate = true }) catch {
        try stdout.print("Error opening struct directory", .{});
        @panic("");
    };

    var iter = member_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != std.fs.Dir.Entry.Kind.file) continue;

        const file_stat = member_dir.statFile(entry.name) catch
            {
            try stdout.print("Error getting stat of a file", .{});
            @panic("");
        };

        file_map.put(entry.name, file_stat) catch @panic("Error adding stat to map");
    }

    return &file_map;
}

/// Use the map of file stat to find the first file with under the bytes limit.
/// return the name of the file. If none is found, return null.
fn getFirstUsableFile(map: *std.StringHashMap(std.fs.File.Stat)) ?[]const u8 {
    var iter = map.keyIterator();
    while (iter.next()) |key| {
        if (std.mem.eql(u8, key.*, "main.zippondata")) continue;
        if (map.get(key.*).?.size < dtypes.parameter_max_file_size_in_bytes) return key.*;
    }
    return null;
}

fn fileName2Index(file_name: []const u8) !usize {
    try stdout.print("Got file name: {s}\n", .{file_name});
    var iter_file_name = std.mem.tokenize(u8, file_name, ".");
    const num_str = iter_file_name.next().?;
    const num: usize = try std.fmt.parseInt(usize, num_str, 10);
    return num;
}

/// Iter over all file and get the max name and return the value of it as i32
/// So for example if there is 1.zippondata and 2.zippondata it return 2.
fn maxFileIndex(map: *std.StringHashMap(std.fs.File.Stat)) usize {
    var iter = map.keyIterator();
    var index_max: usize = 0;
    while (iter.next()) |key| {
        if (std.mem.eql(u8, key.*, "main.zippondata")) continue;
        var iter_file_name = std.mem.tokenize(u8, key.*, ".");
        const num_str = iter_file_name.next().?;
        const num: usize = std.fmt.parseInt(usize, num_str, 10) catch @panic("Error parsing file name into usize");
        if (num > index_max) index_max = num;
    }
    return index_max;
}

const MemberMapError = error{
    NotMemberName,
    NotEqualSign,
    NotStringOrNumber,
    NotComma,
    PuttingNull,
};

/// Take the tokenizer and return a map of the query for the ADD command.
/// Keys are the member name and value are the string of the value in the query. E.g. 'Adrien' or '10'
pub fn getMapOfMember(allocator: Allocator, toker: *ziqlTokenizer) !std.StringHashMap([]const u8) {
    std.debug.print("Started\n\n", .{});
    var token = toker.next();
    std.debug.print("{any}\n\n", .{token});

    var member_map = std.StringHashMap([]const u8).init(
        allocator,
    );

    std.debug.print("OK \n\n", .{});

    while (token.tag != ziqlToken.Tag.eof) : (token = toker.next()) {
        std.debug.print("{any}\n\n", .{token});
        switch (token.tag) {
            .r_paren => continue,
            .invalid => stdout.print("Error: Invalid token: {s}", .{toker.getTokenSlice(token)}) catch {},
            .identifier => {
                const member_name_str = toker.getTokenSlice(token);
                token = toker.next();
                switch (token.tag) {
                    .equal => {
                        token = toker.next();
                        switch (token.tag) {
                            .string_literal, .number_literal => {
                                const value_str = toker.getTokenSlice(token);
                                member_map.put(member_name_str, value_str) catch @panic("Could not add member name and value to map in getMapOfMember");
                                token = toker.next();
                                switch (token.tag) {
                                    .comma, .r_paren => continue,
                                    else => {
                                        stdout.print("Error: Expected , after string or number got: {s}. E.g. ADD User (name='bob', age=10)", .{toker.getTokenSlice(token)}) catch {};
                                        return MemberMapError.NotComma;
                                    },
                                }
                            },
                            .keyword_null => {
                                try stdout.print("Found null value\n", .{});
                                const value_str = "null";
                                member_map.put(member_name_str, value_str) catch {
                                    try stdout.print("Error putting null value into the map\n", .{});
                                    return MemberMapError.PuttingNull;
                                };
                                token = toker.next();
                                switch (token.tag) {
                                    .comma, .r_paren => continue,
                                    else => {
                                        stdout.print("Error: Expected , after string or number got: {s}. E.g. ADD User (name='bob', age=10)", .{toker.getTokenSlice(token)}) catch {};
                                        return MemberMapError.NotComma;
                                    },
                                }
                            },
                            .l_bracket => {
                                var array_values = std.ArrayList([]const u8).init(allocator);
                                token = toker.next();
                                while (token.tag != ziqlToken.Tag.r_bracket) : (token = toker.next()) {
                                    switch (token.tag) {
                                        .string_literal, .number_literal => {
                                            const value_str = toker.getTokenSlice(token);
                                            array_values.append(value_str) catch @panic("Could not add value to array in getMapOfMember");
                                        },
                                        .invalid => stdout.print("Error: Invalid token: {s}", .{toker.getTokenSlice(token)}) catch {},
                                        else => {
                                            stdout.print("Error: Expected string or number in array got: {s}. E.g. ADD User (scores=[10 20 30])", .{toker.getTokenSlice(token)}) catch {};
                                            return MemberMapError.NotStringOrNumber;
                                        },
                                    }
                                }
                                const array_str = try std.mem.join(allocator, " ", array_values.items);
                                member_map.put(member_name_str, array_str) catch @panic("Could not add member name and value to map in getMapOfMember");
                            }, // TODO
                            else => {
                                stdout.print("Error: Expected string or number after a = got: {s}. E.g. ADD User (name='bob')", .{toker.getTokenSlice(token)}) catch {};
                                return MemberMapError.NotStringOrNumber;
                            },
                        }
                    },
                    else => {
                        stdout.print("Error: Expected = after a member declaration get {s}. E.g. ADD User (name='bob')", .{toker.getTokenSlice(token)}) catch {};
                        return MemberMapError.NotEqualSign;
                    },
                }
            },
            else => {
                stdout.print("Error: Unknow token: {s}. This should be the name of a member. E.g. name in ADD User (name='bob')", .{toker.getTokenSlice(token)}) catch {};
                return MemberMapError.NotMemberName;
            },
        }
    }

    return member_map;
}

/// Using the name of a struct from dtypes and the map of member name => value string from the query.
/// Check if the map keys are exactly the same as the name of the member of the struct.
/// Basically checking if the query contain all value that a struct need to be init.
fn checkIfAllMemberInMap(struct_name: []const u8, map: *std.StringHashMap([]const u8)) bool {
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
