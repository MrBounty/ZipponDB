const std = @import("std");
const dataParsing = @import("dataParser.zig");
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

    const DataEngineError = error{
        ErrorCreateDataFolder,
        ErrorCreateStructFolder,
        ErrorCreateMemberFolder,
        ErrorCreateMainFile,
        ErrorCreateDataFile,
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
        var file_names = std.ArrayList([]const u8).init(self.allocator);
        self.getFilesNames(condition.struct_name, condition.member_name, &file_names) catch @panic("Can't get list of files");
        defer file_names.deinit();

        var current_file = file_names.pop();

        var sub_path = std.fmt.allocPrint(self.allocator, "{s}/{s}/{s}/{s}", .{ self.path_to_DATA_dir, condition.struct_name, condition.member_name, current_file }) catch @panic("Can't create sub_path for init a DataIterator");
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
            .int => compare_value = ComparisonValue{ .int = dataParsing.parseInt(condition.value) },
            .str => compare_value = ComparisonValue{ .str = condition.value },
            .float => compare_value = ComparisonValue{ .float = dataParsing.parseFloat(condition.value) },
            .bool => compare_value = ComparisonValue{ .bool_ = dataParsing.parseBool(condition.value) },
            .int_array => compare_value = ComparisonValue{ .int_array = dataParsing.parseArrayInt(self.allocator, condition.value) },
            .str_array => compare_value = ComparisonValue{ .str_array = dataParsing.parseArrayStr(self.allocator, condition.value) },
            .float_array => compare_value = ComparisonValue{ .float_array = dataParsing.parseArrayFloat(self.allocator, condition.value) },
            .bool_array => compare_value = ComparisonValue{ .bool_array = dataParsing.parseArrayBool(self.allocator, condition.value) },
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

        while (true) {
            output_fbs.reset();
            reader.streamUntilDelimiter(writer, '\n', null) catch |err| switch (err) {
                error.EndOfStream => {
                    output_fbs.reset(); // clear buffer before exit
                    self.allocator.free(current_file);

                    if (file_names.items.len == 0) break;

                    current_file = file_names.pop();

                    // Do I leak memory here ? Do I deinit every time ?
                    self.allocator.free(sub_path);
                    sub_path = std.fmt.allocPrint(self.allocator, "{s}/{s}/{s}/{s}", .{ self.path_to_DATA_dir, condition.struct_name, condition.member_name, current_file }) catch @panic("Can't create sub_path for init a DataIterator");

                    // Same here, do I close everytime ?
                    file.close();
                    file = std.fs.cwd().openFile(sub_path, .{}) catch @panic("Can't open first file to init a data iterator");

                    buffered = std.io.bufferedReader(file.reader());
                    reader = buffered.reader();
                    continue;
                }, // file read till the end
                else => {
                    std.debug.print("Error while reading file: {any}\n", .{err});
                    break;
                },
            };

            // TODO: Maybe put that directly inside the union type like a compare function
            // Can also do the switch directly on the compare_value
            // TODO: Add error for wrong condition like superior between 2 string or array
            switch (condition.operation) {
                .equal => {
                    switch (condition.data_type) {
                        .int => if (compare_value.int == dataParsing.parseInt(output_fbs.getWritten()[37..])) try uuid_array.append(try UUID.parse(output_fbs.getWritten()[0..36])),
                        .float => if (compare_value.float == dataParsing.parseFloat(output_fbs.getWritten()[37..])) try uuid_array.append(try UUID.parse(output_fbs.getWritten()[0..36])),
                        .str => if (std.mem.eql(u8, compare_value.str, output_fbs.getWritten()[37..output_fbs.getWritten().len])) try uuid_array.append(try UUID.parse(output_fbs.getWritten()[0..36])),
                        .bool => if (compare_value.bool_ == dataParsing.parseBool(output_fbs.getWritten()[37..])) try uuid_array.append(try UUID.parse(output_fbs.getWritten()[0..36])),
                        // TODO: Implement for array too
                        else => {},
                    }
                },
                .different => {
                    switch (condition.data_type) {
                        .int => if (compare_value.int != dataParsing.parseInt(output_fbs.getWritten()[37..])) try uuid_array.append(try UUID.parse(output_fbs.getWritten()[0..36])),
                        .float => if (compare_value.float != dataParsing.parseFloat(output_fbs.getWritten()[37..])) try uuid_array.append(try UUID.parse(output_fbs.getWritten()[0..36])),
                        .str => if (!std.mem.eql(u8, compare_value.str, output_fbs.getWritten()[38 .. output_fbs.getWritten().len - 1])) try uuid_array.append(try UUID.parse(output_fbs.getWritten()[0..36])),
                        .bool => if (compare_value.bool_ != dataParsing.parseBool(output_fbs.getWritten()[37..])) try uuid_array.append(try UUID.parse(output_fbs.getWritten()[0..36])),
                        // TODO: Implement for array too
                        else => {},
                    }
                },
                .superior_or_equal => {
                    switch (condition.data_type) {
                        .int => if (compare_value.int <= dataParsing.parseInt(output_fbs.getWritten()[37..])) try uuid_array.append(try UUID.parse(output_fbs.getWritten()[0..36])),
                        .float => if (compare_value.float <= dataParsing.parseFloat(output_fbs.getWritten()[37..])) try uuid_array.append(try UUID.parse(output_fbs.getWritten()[0..36])),
                        // TODO: Implement for array too
                        else => {},
                    }
                },
                .superior => {
                    switch (condition.data_type) {
                        .int => if (compare_value.int < dataParsing.parseInt(output_fbs.getWritten()[37..])) try uuid_array.append(try UUID.parse(output_fbs.getWritten()[0..36])),
                        .float => if (compare_value.float < dataParsing.parseFloat(output_fbs.getWritten()[37..])) try uuid_array.append(try UUID.parse(output_fbs.getWritten()[0..36])),
                        // TODO: Implement for array too
                        else => {},
                    }
                },
                .inferior_or_equal => {
                    switch (condition.data_type) {
                        .int => if (compare_value.int >= dataParsing.parseInt(output_fbs.getWritten()[37..])) try uuid_array.append(try UUID.parse(output_fbs.getWritten()[0..36])),
                        .float => if (compare_value.float >= dataParsing.parseFloat(output_fbs.getWritten()[37..])) try uuid_array.append(try UUID.parse(output_fbs.getWritten()[0..36])),
                        // TODO: Implement for array too
                        else => {},
                    }
                },
                .inferior => {
                    switch (condition.data_type) {
                        .int => if (compare_value.int > dataParsing.parseInt(output_fbs.getWritten()[37..])) try uuid_array.append(try UUID.parse(output_fbs.getWritten()[0..36])),
                        .float => if (compare_value.float > dataParsing.parseFloat(output_fbs.getWritten()[37..])) try uuid_array.append(try UUID.parse(output_fbs.getWritten()[0..36])),
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
        const uuid_str = UUID.init().format_uuid();

        const member_names = schemaEngine.structName2structMembers(struct_name);
        for (member_names) |member_name| {
            const potential_file_name_to_use = try self.getFirstUsableFile(struct_name, member_name);

            if (potential_file_name_to_use) |file_name| {
                defer self.allocator.free(file_name);

                const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}/{s}/{s}", .{ self.path_to_DATA_dir, struct_name, member_name, file_name });
                defer self.allocator.free(path);

                var file = std.fs.cwd().openFile(path, .{
                    .mode = .read_write,
                }) catch {
                    std.debug.print("Error opening data file.", .{});
                    continue; // TODO: Error handeling
                };
                defer file.close();

                try file.seekFromEnd(0);
                try file.writer().print("{s} {s}\n", .{ uuid_str, data_map.get(member_name).? });
            } else {
                const max_index = try self.maxFileIndex(struct_name, member_name);

                const new_file_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}/{s}/{d}.zippondata", .{ self.path_to_DATA_dir, struct_name, member_name, max_index + 1 });
                defer self.allocator.free(new_file_path);

                const new_file = std.fs.cwd().createFile(new_file_path, .{}) catch @panic("Error creating new data file");
                defer new_file.close();

                try new_file.writer().print("{s} {s}\n", .{ &uuid_str, data_map.get(member_name).? });
            }
        }

        return UUID.parse(&uuid_str);
    }

    /// Use a filename in the format 1.zippondata and return the 1
    fn fileName2Index(_: FileEngine, file_name: []const u8) usize {
        var iter_file_name = std.mem.tokenize(u8, file_name, ".");
        const num_str = iter_file_name.next().?;
        const num: usize = std.fmt.parseInt(usize, num_str, 10) catch @panic("Couln't parse the int of a zippondata file.");
        return num;
    }

    fn getFilesNames(self: FileEngine, struct_name: []const u8, member_name: []const u8, file_names: *std.ArrayList([]const u8)) !void {
        const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}/{s}", .{ self.path_to_DATA_dir, struct_name, member_name });
        defer self.allocator.free(path);

        var member_dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
        defer member_dir.close();

        var iter = member_dir.iterate();
        defer iter.reset();
        while (try iter.next()) |entry| {
            if ((entry.kind != std.fs.Dir.Entry.Kind.file) or (std.mem.eql(u8, "main.zippondata", entry.name))) continue;
            try file_names.*.append(try self.allocator.dupe(u8, entry.name));
        }
    }

    /// Use the map of file stat to find the first file with under the bytes limit.
    /// return the name of the file. If none is found, return null.
    fn getFirstUsableFile(self: FileEngine, struct_name: []const u8, member_name: []const u8) !?[]const u8 {
        const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}/{s}", .{ self.path_to_DATA_dir, struct_name, member_name });
        defer self.allocator.free(path);

        var member_dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
        defer member_dir.close();

        var iter = member_dir.iterate();
        while (try iter.next()) |entry| {
            if ((entry.kind != std.fs.Dir.Entry.Kind.file) or (std.mem.eql(u8, "main.zippondata", entry.name))) continue;

            const file_stat = try member_dir.statFile(entry.name);
            if (file_stat.size < self.max_file_size) return try self.allocator.dupe(u8, entry.name);
        }
        return null;
    }

    /// Iter over all file and get the max name and return the value of it as usize
    /// So for example if there is 1.zippondata and 2.zippondata it return 2.
    fn maxFileIndex(self: FileEngine, struct_name: []const u8, member_name: []const u8) !usize {
        const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}/{s}", .{ self.path_to_DATA_dir, struct_name, member_name });
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
                else => return DataEngineError.ErrorCreateStructFolder,
            };
            const struct_dir = try data_dir.openDir(struct_name, .{});

            const member_names = schemaEngine.structName2structMembers(struct_name);
            for (member_names) |member_name| {
                struct_dir.makeDir(member_name) catch |err| switch (err) {
                    error.PathAlreadyExists => continue,
                    else => return DataEngineError.ErrorCreateMemberFolder,
                };
                const member_dir = try struct_dir.openDir(member_name, .{});

                _ = member_dir.createFile("0.zippondata", .{}) catch |err| switch (err) {
                    error.PathAlreadyExists => {},
                    else => return DataEngineError.ErrorCreateDataFile,
                };
            }
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
