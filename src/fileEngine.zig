const std = @import("std");
const schemaEngine = @import("schemaEngine.zig");
const Allocator = std.mem.Allocator;
const UUID = @import("types/uuid.zig").UUID;
const DataType = @import("types/dataType.zig").DataType;

//TODO: Create a union class and chose between file and memory

/// Manage everything that is relate to read or write in files
/// Or even get stats, whatever. If it touch files, it's here
pub const FileEngine = struct {
    allocator: Allocator,
    path_to_DATA_dir: []const u8, // The path to the DATA folder
    max_file_size: usize = 5e+4, // 50kb TODO: Change

    pub const Token = struct {
        tag: Tag,
        loc: Loc,

        pub const Loc = struct {
            start: usize,
            end: usize,
        };

        pub const Tag = enum {
            eof,
            invalid,

            string_literal,
            int_literal,
            float_literal,
            identifier,
            equal,
            bang, // !
            pipe, // |
            l_paren, // (
            r_paren, // )
            l_bracket, // [
            r_bracket, // ]
            l_brace, // {
            r_brace, // }
            semicolon, // ;
            comma, // ,
            angle_bracket_left, // <
            angle_bracket_right, // >
            angle_bracket_left_equal, // <=
            angle_bracket_right_equal, // >=
            equal_angle_bracket_right, // =>
            period, // .
            bang_equal, // !=
        };
    };

    pub const Tokenizer = struct {
        buffer: [:0]const u8,
        index: usize,

        // Maybe change that to use the stream directly so I dont have to read the line 2 times
        pub fn init(buffer: [:0]const u8) Tokenizer {
            // Skip the UTF-8 BOM if present.
            return .{
                .buffer = buffer,
                .index = if (std.mem.startsWith(u8, buffer, "\xEF\xBB\xBF")) 3 else 0, // WTF ? I guess some OS add that or some shit like that
            };
        }

        const State = enum {
            start,
            string_literal,
            float,
            int,
        };

        pub fn getTokenSlice(self: *Tokenizer, token: Token) []const u8 {
            return self.buffer[token.loc.start..token.loc.end];
        }

        pub fn next(self: *Tokenizer) Token {
            // That ugly but work
            if (self.buffer[self.index] == ' ') self.index += 1;

            var state: State = .start;
            var result: Token = .{
                .tag = undefined,
                .loc = .{
                    .start = self.index,
                    .end = undefined,
                },
            };
            while (true) : (self.index += 1) {
                const c = self.buffer[self.index];

                if (self.index == self.buffer.len) break;

                switch (state) {
                    .start => switch (c) {
                        '\'' => {
                            state = .string_literal;
                            result.tag = .string_literal;
                        },
                        '0'...'9', '-' => {
                            state = .int;
                            result.tag = .int_literal;
                        },
                        '[' => {
                            result.tag = .l_bracket;
                            self.index += 1;
                            break;
                        },
                        ']' => {
                            result.tag = .r_bracket;
                            self.index += 1;
                            break;
                        },
                        else => std.debug.print("Unknow character: {c}\n", .{c}),
                    },

                    .string_literal => switch (c) {
                        '\'' => {
                            self.index += 1;
                            break;
                        },
                        else => continue,
                    },

                    .int => switch (c) {
                        '.' => {
                            state = .float;
                            result.tag = .float_literal;
                        },
                        '0'...'9' => continue,
                        else => break,
                    },
                    .float => switch (c) {
                        '0'...'9' => {
                            continue;
                        },
                        else => {
                            break;
                        },
                    },
                }
            }

            result.loc.end = self.index;
            return result;
        }
    };

    const ComparisonValue = union {
        int: i64,
        float: f64,
        str: []const u8,
        bool_: bool,
        int_array: std.ArrayList(i64),
        str_array: std.ArrayList([]const u8),
        float_array: std.ArrayList(f64),
        bool_array: std.ArrayList(bool),
    };

    /// use to parse file. It take a struct name and member name to know what to parse.
    /// An Operation from equal, different, superior, superior_or_equal, ...
    /// The DataType from int, float and str
    pub const Condition = struct {
        struct_name: []const u8,
        member_name: []const u8 = undefined,
        value: []const u8 = undefined,
        operation: enum { equal, different, superior, superior_or_equal, inferior, inferior_or_equal } = undefined, // Add more stuff like IN
        data_type: DataType = undefined,

        pub fn init(struct_name: []const u8) Condition {
            return Condition{ .struct_name = struct_name };
        }
    };

    pub fn init(allocator: Allocator, DATA_path: ?[]const u8) FileEngine {
        // I think use env variable for the path, idk, something better at least than just that 😕
        return FileEngine{
            .allocator = allocator,
            .path_to_DATA_dir = DATA_path orelse "ZipponDB/DATA",
        };
    }

    /// Take a condition and an array of UUID and fill the array with all UUID that match the condition
    pub fn getUUIDListUsingCondition(self: *FileEngine, condition: Condition, uuid_array: *std.ArrayList(UUID)) !void {
        const max_file_index = try self.maxFileIndex(condition.struct_name);
        var current_index: usize = 0;

        var sub_path = std.fmt.allocPrint(self.allocator, "{s}/{s}/{d}.zippondata", .{ self.path_to_DATA_dir, condition.struct_name, current_index }) catch @panic("Can't create sub_path for init a DataIterator");
        defer self.allocator.free(sub_path);

        var file = std.fs.cwd().openFile(sub_path, .{}) catch @panic("Can't open first file to init a data iterator");
        defer file.close();

        var output: [1024 * 50]u8 = undefined; // Maybe need to increase that as it limit the size of a line in a file
        var output_fbs = std.io.fixedBufferStream(&output);
        const writer = output_fbs.writer();

        var buffered = std.io.bufferedReader(file.reader());
        var reader = buffered.reader();

        var compare_value: ComparisonValue = undefined;
        switch (condition.data_type) {
            .int => compare_value = ComparisonValue{ .int = parseInt(condition.value) },
            .str => compare_value = ComparisonValue{ .str = condition.value },
            .float => compare_value = ComparisonValue{ .float = parseFloat(condition.value) },
            .bool => compare_value = ComparisonValue{ .bool_ = parseBool(condition.value) },
            .int_array => compare_value = ComparisonValue{ .int_array = parseArrayInt(self.allocator, condition.value) },
            .str_array => compare_value = ComparisonValue{ .str_array = parseArrayStr(self.allocator, condition.value) },
            .float_array => compare_value = ComparisonValue{ .float_array = parseArrayFloat(self.allocator, condition.value) },
            .bool_array => compare_value = ComparisonValue{ .bool_array = parseArrayBool(self.allocator, condition.value) },
        }
        defer {
            switch (condition.data_type) {
                .int_array => compare_value.int_array.deinit(),
                .str_array => compare_value.str_array.deinit(),
                .float_array => compare_value.float_array.deinit(),
                .bool_array => compare_value.bool_array.deinit(),
                else => {},
            }
        }

        var token: FileEngine.Token = undefined;
        const column_index = schemaEngine.columnIndexOfMember(condition.struct_name, condition.member_name);

        while (true) {
            output_fbs.reset();
            reader.streamUntilDelimiter(writer, '\n', null) catch |err| switch (err) {
                error.EndOfStream => {
                    output_fbs.reset(); // clear buffer before exit

                    if (current_index == max_file_index) break;

                    current_index += 1;

                    self.allocator.free(sub_path);
                    sub_path = std.fmt.allocPrint(self.allocator, "{s}/{s}/{d}.zippondata", .{ self.path_to_DATA_dir, condition.struct_name, current_index }) catch @panic("Can't create sub_path for init a DataIterator");

                    file.close(); // Do I need to close ? I think so
                    file = std.fs.cwd().openFile(sub_path, .{}) catch {
                        std.debug.print("Error trying to open {s}\n", .{sub_path});
                        @panic("Can't open first file to init a data iterator");
                    };

                    buffered = std.io.bufferedReader(file.reader());
                    reader = buffered.reader();
                    continue;
                }, // file read till the end
                else => {
                    std.debug.print("Error while reading file: {any}\n", .{err});
                    break;
                },
            };

            // Maybe use the stream directly to prevent duplicate the data
            // But I would need to change the Tokenizer a lot...
            const null_terminated_string = try self.allocator.dupeZ(u8, output_fbs.getWritten()[37..]);
            defer self.allocator.free(null_terminated_string);

            var data_toker = Tokenizer.init(null_terminated_string);
            const uuid = try UUID.parse(output_fbs.getWritten()[0..36]);

            // Skip unwanted token
            for (0..column_index.?) |_| {
                _ = data_toker.next();
            }

            token = data_toker.next();

            // TODO: Add error for wrong condition like superior between 2 string or array
            switch (condition.operation) {
                .equal => {
                    switch (condition.data_type) {
                        .int => if (compare_value.int == parseInt(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                        .float => if (compare_value.float == parseFloat(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                        .str => if (std.mem.eql(u8, compare_value.str, data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                        .bool => if (compare_value.bool_ == parseBool(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                        // TODO: Implement for array too
                        else => {},
                    }
                },

                .different => {
                    switch (condition.data_type) {
                        .int => if (compare_value.int != parseInt(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                        .float => if (compare_value.float != parseFloat(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                        .str => if (!std.mem.eql(u8, compare_value.str, data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                        .bool => if (compare_value.bool_ != parseBool(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                        // TODO: Implement for array too
                        else => {},
                    }
                },

                .superior_or_equal => {
                    switch (condition.data_type) {
                        .int => if (compare_value.int <= parseInt(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                        .float => if (compare_value.float <= parseFloat(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                        // TODO: Implement for array too
                        else => {},
                    }
                },

                .superior => {
                    switch (condition.data_type) {
                        .int => if (compare_value.int < parseInt(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                        .float => if (compare_value.float < parseFloat(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                        // TODO: Implement for array too
                        else => {},
                    }
                },

                .inferior_or_equal => {
                    switch (condition.data_type) {
                        .int => if (compare_value.int >= parseInt(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                        .float => if (compare_value.float >= parseFloat(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                        // TODO: Implement for array too
                        else => {},
                    }
                },

                .inferior => {
                    switch (condition.data_type) {
                        .int => if (compare_value.int > parseInt(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                        .float => if (compare_value.float > parseFloat(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                        // TODO: Implement for array too
                        else => {},
                    }
                },
            }
        }
    }

    // TODO: Clean a bit the code
    // Do I need multiple files too ? I mean it duplicate UUID a lot, if it's just to save a name like 'Bob', storing a long UUID is overkill
    // I could just use a tabular data format with separator using space - Or maybe I encode the uuid to take a minimum space as I always know it size
    pub fn writeEntity(self: FileEngine, struct_name: []const u8, data_map: std.StringHashMap([]const u8)) !UUID {
        const uuid = UUID.init();

        const potential_file_index = try self.getFirstUsableIndexFile(struct_name);
        var file: std.fs.File = undefined;
        defer file.close();

        var path: []const u8 = undefined;
        defer self.allocator.free(path);

        if (potential_file_index) |file_index| {
            path = try std.fmt.allocPrint(self.allocator, "{s}/{s}/{d}.zippondata", .{ self.path_to_DATA_dir, struct_name, file_index });
            file = std.fs.cwd().openFile(path, .{ .mode = .read_write }) catch @panic("=(");
        } else {
            const max_index = try self.maxFileIndex(struct_name);

            path = try std.fmt.allocPrint(self.allocator, "{s}/{s}/{d}.zippondata", .{ self.path_to_DATA_dir, struct_name, max_index + 1 });
            file = std.fs.cwd().createFile(path, .{}) catch @panic("Error creating new data file");
        }

        try file.seekFromEnd(0);
        try file.writer().print("{s}", .{uuid.format_uuid()});

        const member_names = schemaEngine.structName2structMembers(struct_name); // This need to be in the same order all the time tho
        for (member_names) |member_name| {
            try file.writer().print(" {s}", .{data_map.get(member_name).?});
        }

        try file.writer().print("\n", .{});

        return uuid;
    }

    /// Use a filename in the format 1.zippondata and return the 1
    /// Note that if I change the extension of the data file, I need to update that as it use a fixed len for the extension
    fn fileName2Index(_: FileEngine, file_name: []const u8) usize {
        return std.fmt.parseInt(usize, file_name[0..(file_name.len - 11)], 10) catch @panic("Couln't parse the int of a zippondata file.");
    }

    /// Use the map of file stat to find the first file with under the bytes limit.
    /// return the name of the file. If none is found, return null.
    fn getFirstUsableIndexFile(self: FileEngine, struct_name: []const u8) !?usize {
        const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.path_to_DATA_dir, struct_name });
        defer self.allocator.free(path);

        var member_dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
        defer member_dir.close();

        var iter = member_dir.iterate();
        while (try iter.next()) |entry| {
            const file_stat = try member_dir.statFile(entry.name);
            if (file_stat.size < self.max_file_size) return self.fileName2Index(entry.name);
        }
        return null;
    }

    /// Iter over all file and get the max name and return the value of it as usize
    /// So for example if there is 1.zippondata and 2.zippondata it return 2.
    fn maxFileIndex(self: FileEngine, struct_name: []const u8) !usize {
        const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.path_to_DATA_dir, struct_name });
        defer self.allocator.free(path);

        const member_dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
        var count: usize = 0;

        var iter = member_dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != std.fs.Dir.Entry.Kind.file) continue;
            count += 1;
        }
        return count - 1;
    }

    // TODO: Give the option to keep , dump or erase the data
    pub fn initDataFolder(self: FileEngine) !void {
        var data_dir = try std.fs.cwd().openDir(self.path_to_DATA_dir, .{});
        defer data_dir.close();

        for (schemaEngine.struct_name_list) |struct_name| {
            data_dir.makeDir(struct_name) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };
            const struct_dir = try data_dir.openDir(struct_name, .{});

            _ = struct_dir.createFile("0.zippondata", .{}) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };
        }
    }
};

test "Get list of UUID using condition" {
    const allocator = std.testing.allocator;
    var data_engine = FileEngine.init(allocator, null);

    var uuid_array = std.ArrayList(UUID).init(allocator);
    defer uuid_array.deinit();

    const condition = FileEngine.Condition{ .struct_name = "User", .member_name = "email", .value = "adrien@mail.com", .operation = .equal, .data_type = .str };
    try data_engine.getUUIDListUsingCondition(condition, &uuid_array);
}

test "Open dir" {
    const dir = std.fs.cwd();
    const sub_dir = try dir.openDir("src/types", .{});
    _ = sub_dir;
}

// Series of functions to use just before creating an entity.
// Will transform the string of data into data of the right type./

pub fn parseInt(value_str: []const u8) i64 {
    return std.fmt.parseInt(i64, value_str, 10) catch return 0;
}

pub fn parseArrayInt(allocator: std.mem.Allocator, array_str: []const u8) std.ArrayList(i64) {
    var array = std.ArrayList(i64).init(allocator);

    var it = std.mem.splitAny(u8, array_str[1 .. array_str.len - 1], " ");
    while (it.next()) |x| {
        array.append(parseInt(x)) catch {};
    }

    return array;
}

pub fn parseFloat(value_str: []const u8) f64 {
    return std.fmt.parseFloat(f64, value_str) catch return 0;
}

pub fn parseArrayFloat(allocator: std.mem.Allocator, array_str: []const u8) std.ArrayList(f64) {
    var array = std.ArrayList(f64).init(allocator);

    var it = std.mem.splitAny(u8, array_str[1 .. array_str.len - 1], " ");
    while (it.next()) |x| {
        array.append(parseFloat(x)) catch {};
    }

    return array;
}

pub fn parseBool(value_str: []const u8) bool {
    return (value_str[0] != '0');
}

pub fn parseArrayBool(allocator: std.mem.Allocator, array_str: []const u8) std.ArrayList(bool) {
    var array = std.ArrayList(bool).init(allocator);

    var it = std.mem.splitAny(u8, array_str[1 .. array_str.len - 1], " ");
    while (it.next()) |x| {
        array.append(parseBool(x)) catch {};
    }

    return array;
}

// FIXME: This will not work if their is a space in one string. E.g ['Hello world'] will be split between Hello and world but it shouldn't
pub fn parseArrayStr(allocator: std.mem.Allocator, array_str: []const u8) std.ArrayList([]const u8) {
    var array = std.ArrayList([]const u8).init(allocator);

    var it = std.mem.splitAny(u8, array_str[1 .. array_str.len - 1], " ");
    while (it.next()) |x| {
        const x_copy = allocator.dupe(u8, x) catch @panic("=(");
        array.append(x_copy) catch {};
    }

    return array;
}

test "Data parsing" {
    const allocator = std.testing.allocator;

    // Int
    const in1: [3][]const u8 = .{ "1", "42", "Hello" };
    const expected_out1: [3]i64 = .{ 1, 42, 0 };
    for (in1, 0..) |value, i| {
        try std.testing.expect(parseInt(value) == expected_out1[i]);
    }

    // Int array
    const in2 = "[1 14 44 42 hello]";
    const out2 = parseArrayInt(allocator, in2);
    defer out2.deinit();
    const expected_out2: [5]i64 = .{ 1, 14, 44, 42, 0 };
    try std.testing.expect(std.mem.eql(i64, out2.items, &expected_out2));

    // Float
    const in3: [3][]const u8 = .{ "1.3", "65.991", "Hello" };
    const expected_out3: [3]f64 = .{ 1.3, 65.991, 0 };
    for (in3, 0..) |value, i| {
        try std.testing.expect(parseFloat(value) == expected_out3[i]);
    }

    // Float array
    const in4 = "[1.5 14.3 44.9999 42 hello]";
    const out4 = parseArrayFloat(allocator, in4);
    defer out4.deinit();
    const expected_out4: [5]f64 = .{ 1.5, 14.3, 44.9999, 42, 0 };
    try std.testing.expect(std.mem.eql(f64, out4.items, &expected_out4));

    // Bool
    const in5: [3][]const u8 = .{ "1", "Hello", "0" };
    const expected_out5: [3]bool = .{ true, true, false };
    for (in5, 0..) |value, i| {
        try std.testing.expect(parseBool(value) == expected_out5[i]);
    }

    // Bool array
    const in6 = "[1 0 0 1 1]";
    const out6 = parseArrayBool(allocator, in6);
    defer out6.deinit();
    const expected_out6: [5]bool = .{ true, false, false, true, true };
    try std.testing.expect(std.mem.eql(bool, out6.items, &expected_out6));

    // TODO: Test the string array
}

// Test tokenizer

test "basic query" {
    try testTokenize("001 123 0185", &.{ .int_literal, .int_literal, .int_literal });
}

fn testTokenize(source: [:0]const u8, expected_token_tags: []const FileEngine.Token.Tag) !void {
    var tokenizer = FileEngine.Tokenizer.init(source);
    for (expected_token_tags) |expected_token_tag| {
        const token = tokenizer.next();
        try std.testing.expectEqual(expected_token_tag, token.tag);
    }
}
