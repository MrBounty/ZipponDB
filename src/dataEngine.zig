const std = @import("std");
const dataParsing = @import("data-parsing.zig");
const metadata = @import("metadata.zig");
const Allocator = std.mem.Allocator;
const UUID = @import("uuid.zig").UUID;
const stdout = std.io.getStdOut().writer();

/// Manage everything that is relate to read or write in files
/// Or even get stats, whatever. If it touch files, it's here
pub const DataEngine = struct {
    allocator: Allocator,
    dir: std.fs.Dir, // The path to the DATA folder
    max_file_size: usize = 1e+8, // 100mb
    //
    const DataEngineError = error{
        ErrorCreateDataFolder,
        ErrorCreateStructFolder,
        ErrorCreateMemberFolder,
        ErrorCreateMainFile,
        ErrorCreateDataFile,
    };

    /// Suported operation for the filter
    /// TODO: Add more operation, like IN for array and LIKE for regex
    const Operation = enum {
        equal,
        different,
        superior,
        superior_or_equal,
        inferior,
        inferior_or_equal,
    };

    /// Suported dataType for the DB
    const DataType = enum {
        int,
        float,
        str,
        bool_,
        int_array,
        float_array,
        str_array,
        bool_array,
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
    /// TODO: Change the value to be the right type and not just a string all the time
    const Condition = struct {
        struct_name: []const u8,
        member_name: []const u8,
        value: []const u8,
        operation: Operation,
        data_type: DataType,
    };

    pub fn init(allocator: Allocator, DATA_path: ?[]const u8) DataEngine {
        const path = DATA_path orelse "ZipponDB/DATA";
        const dir = std.fs.cwd().openDir(path, .{}) catch @panic("Error opening ZipponDB/DATA");
        return DataEngine{
            .allocator = allocator,
            .dir = dir,
        };
    }

    pub fn deinit(self: *DataEngine) void {
        self.dir.close();
    }

    /// Take a condition and an array of UUID and fill the array with all UUID that match the condition
    pub fn getUUIDListUsingCondition(self: *DataEngine, condition: Condition, uuid_array: *std.ArrayList(UUID)) !void {
        const file_names = self.getFilesNames(condition.struct_name, condition.member_name) catch @panic("Can't get list of files");
        defer self.deinitFilesNames(&file_names);

        const sub_path = std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}/{s}",
            .{ condition.struct_name, condition.member_name, file_names.items[0] },
        ) catch @panic("Can't create sub_path for init a DataIterator");
        defer self.allocator.free(sub_path);

        var file = self.dir.openFile(sub_path, .{}) catch @panic("Can't open first file to init a data iterator");
        // defer self.allocator.free(sub_path);

        var output: [1024 * 50]u8 = undefined; // Maybe need to increase that as it limit the size of a line in files
        var output_fbs = std.io.fixedBufferStream(&output);
        const writer = output_fbs.writer();

        var buffered = std.io.bufferedReader(file.reader());
        var reader = buffered.reader();

        var file_index: usize = 0;

        var compare_value: ComparisonValue = undefined;
        switch (condition.data_type) {
            .int => compare_value = ComparisonValue{ .int = dataParsing.parseInt(condition.value) },
            .str => compare_value = ComparisonValue{ .str = condition.value },
            .float => compare_value = ComparisonValue{ .float = dataParsing.parseFloat(condition.value) },
            .bool_ => compare_value = ComparisonValue{ .bool_ = dataParsing.parseBool(condition.value) },
            .int_array => compare_value = ComparisonValue{ .int_array = dataParsing.parseArrayInt(self.allocator, condition.value) },
            .str_array => compare_value = ComparisonValue{ .str_array = dataParsing.parseArrayStr(self.allocator, condition.value) },
            .float_array => compare_value = ComparisonValue{ .float_array = dataParsing.parseArrayFloat(self.allocator, condition.value) },
            .bool_array => compare_value = ComparisonValue{ .bool_array = dataParsing.parseArrayBool(self.allocator, condition.value) },
        }

        while (true) {
            output_fbs.reset();
            reader.streamUntilDelimiter(writer, '\n', null) catch |err| switch (err) {
                error.EndOfStream => {
                    output_fbs.reset(); // clear buffer before exit
                    file_index += 1;

                    if (file_index == file_names.items.len) break;

                    // TODO: Update the file and reader to be the next file of the list

                    break;
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
                        .str => if (std.mem.eql(u8, compare_value.str, output_fbs.getWritten()[38 .. output_fbs.getWritten().len - 1])) try uuid_array.append(try UUID.parse(output_fbs.getWritten()[0..36])),
                        .bool_ => if (compare_value.bool_ == dataParsing.parseBool(output_fbs.getWritten()[37..])) try uuid_array.append(try UUID.parse(output_fbs.getWritten()[0..36])),
                        // TODO: Implement for array too
                        else => {},
                    }
                },
                .different => {
                    switch (condition.data_type) {
                        .int => if (compare_value.int != dataParsing.parseInt(output_fbs.getWritten()[37..])) try uuid_array.append(try UUID.parse(output_fbs.getWritten()[0..36])),
                        .float => if (compare_value.float != dataParsing.parseFloat(output_fbs.getWritten()[37..])) try uuid_array.append(try UUID.parse(output_fbs.getWritten()[0..36])),
                        .str => if (!std.mem.eql(u8, compare_value.str, output_fbs.getWritten()[38 .. output_fbs.getWritten().len - 1])) try uuid_array.append(try UUID.parse(output_fbs.getWritten()[0..36])),
                        .bool_ => if (compare_value.bool_ != dataParsing.parseBool(output_fbs.getWritten()[37..])) try uuid_array.append(try UUID.parse(output_fbs.getWritten()[0..36])),
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

    // TODO: Test leak on that
    pub fn writeEntity(self: *DataEngine, struct_name: []const u8, data_map: std.StringHashMap([]const u8)) !void {
        const uuid_str = UUID.init().format_uuid();
        defer stdout.print("Added new {s} successfully using UUID: {s}\n", .{
            struct_name,
            uuid_str,
        }) catch {};

        const member_names = metadata.structName2structMembers(struct_name);
        for (member_names) |member_name| {
            const potential_file_name_to_use = try self.getFirstUsableFile(struct_name, member_name);

            if (potential_file_name_to_use) |file_name| {
                defer self.allocator.free(file_name);

                const file_index = self.fileName2Index(file_name);

                const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}/{s}", .{
                    struct_name,
                    member_name,
                    file_name,
                });
                defer self.allocator.free(path);

                var file = self.dir.openFile(path, .{
                    .mode = .read_write,
                }) catch {
                    try stdout.print("Error opening data file.", .{});
                    return;
                };
                defer file.close();

                try file.seekFromEnd(0);
                try file.writer().print("{s} {s}\n", .{ uuid_str, data_map.get(member_name).? });

                const path_to_main = try std.fmt.allocPrint(self.allocator, "{s}/{s}/main.zippondata", .{
                    struct_name,
                    member_name,
                });
                defer self.allocator.free(path_to_main);

                var file_main = self.dir.openFile(path_to_main, .{
                    .mode = .read_write,
                }) catch {
                    try stdout.print("Error opening data file.", .{});
                    return;
                };
                defer file_main.close();

                try self.addUUIDToMainFile(file_main, file_index + 1, &uuid_str);
            } else {
                const max_index = try self.maxFileIndex(struct_name, member_name);

                const new_file_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}/{d}.zippondata", .{
                    struct_name,
                    member_name,
                    max_index + 1,
                });

                try stdout.print("new file path: {s}\n", .{new_file_path});

                // TODO: Create new file and save the data inside
                const new_file = self.dir.createFile(new_file_path, .{}) catch @panic("Error creating new data file");
                defer new_file.close();

                try new_file.writer().print("{s} {s}\n", .{ &uuid_str, data_map.get(member_name).? });

                const path_to_main = try std.fmt.allocPrint(self.allocator, "ZipponDB/DATA/{s}/{s}/main.zippondata", .{
                    struct_name,
                    member_name,
                });
                defer self.allocator.free(path_to_main);

                var file_main = self.dir.openFile(path_to_main, .{
                    .mode = .read_write,
                }) catch {
                    try stdout.print("Error opening data file.", .{});
                    @panic("");
                };
                defer file_main.close();

                try file_main.seekFromEnd(0);
                try file_main.writeAll("\n ");
                try file_main.seekTo(0);
                try self.addUUIDToMainFile(file_main, max_index + 1, &uuid_str);
            }
        }
    }

    /// Use a filename in the format 1.zippondata and return the 1
    fn fileName2Index(_: *DataEngine, file_name: []const u8) usize {
        var iter_file_name = std.mem.tokenize(u8, file_name, ".");
        const num_str = iter_file_name.next().?;
        const num: usize = std.fmt.parseInt(usize, num_str, 10) catch @panic("Couln't parse the int of a zippondata file.");
        return num;
    }

    /// Add an UUID at a specific index of a file
    /// Used when some data are deleted from previous zippondata files and are now bellow the file size limit
    fn addUUIDToMainFile(_: *DataEngine, file: std.fs.File, index: usize, uuid_str: []const u8) !void {
        var output: [1024 * 50]u8 = undefined; // Maybe need to increase that as it limit the size of a line in files
        var output_fbs = std.io.fixedBufferStream(&output);
        const writer = output_fbs.writer();

        var reader = file.reader();

        var line_num: usize = 1;
        while (true) {
            output_fbs.reset();
            reader.streamUntilDelimiter(writer, '\n', null) catch |err| switch (err) { // Maybe do a better error handeling. Because if an error happend here, data are already written in files but not in main
                error.EndOfStream => {
                    output_fbs.reset(); // clear buffer before exit
                    break;
                }, // file read till the end
                else => break,
            };

            if (line_num == index) {
                try file.seekBy(-1);
                try file.writer().print("{s}  ", .{uuid_str});
                return;
            }
            line_num += 1;
        }
    }

    fn getFilesNames(self: *DataEngine, struct_name: []const u8, member_name: []const u8) !std.ArrayList([]const u8) {
        const sub_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ struct_name, member_name });

        var file_names = std.ArrayList([]const u8).init(self.allocator);

        const member_dir = self.dir.openDir(sub_path, .{ .iterate = true }) catch @panic("Error opening member directory");
        defer self.allocator.free(sub_path);

        var iter = member_dir.iterate();
        while (try iter.next()) |entry| {
            if ((entry.kind != std.fs.Dir.Entry.Kind.file) or (std.mem.eql(u8, "main.zippondata", entry.name))) continue;
            try file_names.append(try self.allocator.dupe(u8, entry.name));
        }

        return file_names;
    }

    fn deinitFilesNames(self: *DataEngine, array: *const std.ArrayList([]const u8)) void {
        for (array.items) |elem| {
            self.allocator.free(elem);
        }
        array.deinit();
    }

    /// Use the map of file stat to find the first file with under the bytes limit.
    /// return the name of the file. If none is found, return null.
    fn getFirstUsableFile(self: *DataEngine, struct_name: []const u8, member_name: []const u8) !?[]const u8 {
        const sub_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ struct_name, member_name });
        defer self.allocator.free(sub_path);
        var member_dir = try self.dir.openDir(sub_path, .{ .iterate = true });
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
    fn maxFileIndex(self: *DataEngine, struct_name: []const u8, member_name: []const u8) !usize {
        const buffer = try self.allocator.alloc(u8, 1024); // Adjust the size as needed
        defer self.allocator.free(buffer);

        const sub_path = try std.fmt.bufPrint(buffer, "{s}/{s}", .{ struct_name, member_name });
        const member_dir = try self.dir.openDir(sub_path, .{ .iterate = true });
        var count: usize = 0;

        var iter = member_dir.iterate();
        while (try iter.next()) |entry| {
            if ((entry.kind != std.fs.Dir.Entry.Kind.file) or (std.mem.eql(u8, "main.zippondata", entry.name))) continue;
            count += 1;
        }
        return count;
    }

    // TODO: Give the option to keep , dump or erase the data
    pub fn initDataFolder(self: *DataEngine) !void {
        for (metadata.struct_name_list) |struct_name| {
            self.dir.makeDir(struct_name) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return DataEngineError.ErrorCreateStructFolder,
            };
            const struct_dir = try self.dir.openDir(struct_name, .{});

            const member_names = metadata.structName2structMembers(struct_name);
            for (member_names) |member_name| {
                struct_dir.makeDir(member_name) catch |err| switch (err) {
                    error.PathAlreadyExists => continue,
                    else => return DataEngineError.ErrorCreateMemberFolder,
                };
                const member_dir = try struct_dir.openDir(member_name, .{});

                blk: {
                    const file = member_dir.createFile("main.zippondata", .{}) catch |err| switch (err) {
                        error.PathAlreadyExists => break :blk,
                        else => return DataEngineError.ErrorCreateMainFile,
                    };
                    try file.writeAll("\n");
                }
                _ = member_dir.createFile("0.zippondata", .{}) catch |err| switch (err) {
                    error.PathAlreadyExists => {},
                    else => return DataEngineError.ErrorCreateDataFile,
                };
            }
        }
    }
};

test "File iterator" {
    const allocator = std.testing.allocator;
    var data_engine = DataEngine.init(allocator, null);

    var uuid_array = std.ArrayList(UUID).init(allocator);
    defer uuid_array.deinit();

    const condition = DataEngine.Condition{ .struct_name = "User", .member_name = "email", .value = "adrien@mail.com", .operation = .equal, .data_type = .str };
    try data_engine.getUUIDListUsingCondition(condition, &uuid_array);

    std.debug.print("Found {d} uuid with first as {any}\n\n", .{ uuid_array.items.len, uuid_array.items[0] });
}
