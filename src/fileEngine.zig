const std = @import("std");
const Allocator = std.mem.Allocator;
const UUID = @import("types/uuid.zig").UUID;
const DataType = @import("types/dataType.zig").DataType;
const FileTokenizer = @import("tokenizers/file.zig").Tokenizer;
const FileToken = @import("tokenizers/file.zig").Token;
const SchemaStruct = @import("schemaParser.zig").Parser.SchemaStruct;
const SchemaParser = @import("schemaParser.zig").Parser;
const SchemaTokenizer = @import("tokenizers/schema.zig").Tokenizer;
const SchemaToken = @import("tokenizers/schema.zig").Token;
const AdditionalData = @import("ziqlParser.zig").Parser.AdditionalData;

//TODO: Create a union class and chose between file and memory

/// Manage everything that is relate to read or write in files
/// Or even get stats, whatever. If it touch files, it's here
pub const FileEngine = struct {
    allocator: Allocator,
    usable: bool,
    path_to_ZipponDB_dir: []const u8, // Make that into a list
    max_file_size: usize = 5e+4, // 50kb TODO: Change
    null_terminated_schema_buff: [:0]u8,
    struct_array: std.ArrayList(SchemaStruct),

    pub fn init(allocator: Allocator, path: []const u8) FileEngine {
        const path_to_ZipponDB_dir = path;

        var schema_buf = allocator.alloc(u8, 1024 * 50) catch @panic("Cant allocate the schema buffer");
        defer allocator.free(schema_buf);

        const len: usize = FileEngine.readSchemaFile(allocator, path_to_ZipponDB_dir, schema_buf) catch 0;
        const null_terminated_schema_buff = allocator.dupeZ(u8, schema_buf[0..len]) catch @panic("Cant allocate null term buffer for the schema");

        var toker = SchemaTokenizer.init(null_terminated_schema_buff);
        var parser = SchemaParser.init(&toker, allocator);

        var struct_array = std.ArrayList(SchemaStruct).init(allocator);
        parser.parse(&struct_array) catch {};

        return FileEngine{
            .allocator = allocator,
            .path_to_ZipponDB_dir = path_to_ZipponDB_dir,
            .null_terminated_schema_buff = null_terminated_schema_buff,
            .struct_array = struct_array,
            .usable = !std.mem.eql(u8, path, ""),
        };
    }

    pub fn deinit(self: *FileEngine) void {
        for (self.struct_array.items) |*elem| elem.deinit();
        self.struct_array.deinit();
        self.allocator.free(self.null_terminated_schema_buff);
        self.allocator.free(self.path_to_ZipponDB_dir);
    }

    const ComparisonValue = union {
        int: i64,
        float: f64,
        str: []const u8,
        bool_: bool,
        id: UUID,
        int_array: std.ArrayList(i64),
        str_array: std.ArrayList([]const u8),
        float_array: std.ArrayList(f64),
        bool_array: std.ArrayList(bool),
        id_array: std.ArrayList(UUID),
    };

    /// use to parse file. It take a struct name and member name to know what to parse.
    /// An Operation from equal, different, superior, superior_or_equal, ...
    /// The DataType from int, float and str
    pub const Condition = struct {
        struct_name: []const u8,
        member_name: []const u8 = undefined,
        value: []const u8 = undefined,
        operation: enum { equal, different, superior, superior_or_equal, inferior, inferior_or_equal, in } = undefined, // Add more stuff like IN
        data_type: DataType = undefined,

        pub fn init(struct_name: []const u8) Condition {
            return Condition{ .struct_name = struct_name };
        }
    };

    pub fn setPath(self: *FileEngine, path: []const u8) void {
        self.path_to_ZipponDB_dir = path;
    }

    /// Take a list of UUID and, a buffer array and the additional data to write into the buffer the JSON to send
    /// TODO: Optimize
    /// FIXME: Array of string are not working
    pub fn parseAndWriteToSend(self: *FileEngine, struct_name: []const u8, uuids: []UUID, buffer: *std.ArrayList(u8), additional_data: AdditionalData) !void {
        const max_file_index = try self.maxFileIndex(struct_name);
        var current_index: usize = 0;

        var path_buff = std.fmt.allocPrint(self.allocator, "{s}/DATA/{s}/{d}.zippondata", .{ self.path_to_ZipponDB_dir, struct_name, current_index }) catch @panic("Can't create sub_path for init a DataIterator");
        defer self.allocator.free(path_buff);

        var file = std.fs.cwd().openFile(path_buff, .{}) catch {
            std.debug.print("Path: {s}", .{path_buff});
            @panic("Can't open first file to init a data iterator");
        };
        defer file.close();

        var output: [1024 * 50]u8 = undefined; // Maybe need to increase that as it limit the size of a line in a file
        var output_fbs = std.io.fixedBufferStream(&output);
        const writer = output_fbs.writer();

        var buffered = std.io.bufferedReader(file.reader());
        var reader = buffered.reader();
        var founded = false;
        var token: FileToken = undefined;

        var out_writer = buffer.writer();
        try out_writer.writeAll("[");

        // Write the start {

        while (true) {
            output_fbs.reset();
            reader.streamUntilDelimiter(writer, '\n', null) catch |err| switch (err) {
                error.EndOfStream => {
                    // When end of file, check if all file was parse, if not update the reader to the next file
                    // TODO: Be able to give an array of file index from the B+Tree to only parse them
                    output_fbs.reset(); // clear buffer before exit

                    if (current_index == max_file_index) break;

                    current_index += 1;

                    self.allocator.free(path_buff);
                    path_buff = std.fmt.allocPrint(self.allocator, "{s}/DATA/{s}/{d}.zippondata", .{ self.path_to_ZipponDB_dir, struct_name, current_index }) catch @panic("Can't create sub_path for init a DataIterator");

                    file.close(); // Do I need to close ? I think so
                    file = std.fs.cwd().openFile(path_buff, .{}) catch {
                        std.debug.print("Error trying to open {s}\n", .{path_buff});
                        @panic("Can't open file to update a data iterator");
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

            const null_terminated_string = try self.allocator.dupeZ(u8, output_fbs.getWritten()[37..]);
            defer self.allocator.free(null_terminated_string);

            var data_toker = FileTokenizer.init(null_terminated_string);
            const uuid = try UUID.parse(output_fbs.getWritten()[0..36]);

            founded = false;
            // Optimize this
            for (uuids) |elem| {
                if (elem.compare(uuid)) {
                    founded = true;
                    break;
                }
            }

            if (founded) {
                try out_writer.writeAll("{");
                try out_writer.writeAll("id:\"");
                try out_writer.print("{s}", .{output_fbs.getWritten()[0..36]});
                try out_writer.writeAll("\", ");
                for (self.structName2structMembers(struct_name), self.structName2DataType(struct_name)) |member_name, member_type| {
                    token = data_toker.next();
                    // FIXME: When relationship will be implemented, need to check if the len of NON link is 0
                    if ((additional_data.member_to_find.items.len == 0) or (self.isMemberNameInAdditionalData(self.locToSlice(member_name), additional_data))) {
                        // write the member name and = sign
                        try out_writer.print("{s}: ", .{self.locToSlice(member_name)});

                        switch (member_type) {
                            .str => {
                                const str_slice = data_toker.getTokenSlice(token);
                                try out_writer.print("\"{s}\"", .{str_slice[1 .. str_slice.len - 1]});
                            },
                            .str_array => {
                                try out_writer.writeAll(data_toker.getTokenSlice(token));
                                token = data_toker.next();
                                while (token.tag != .r_bracket) : (token = data_toker.next()) {
                                    try out_writer.writeAll("\"");
                                    try out_writer.writeAll(data_toker.getTokenSlice(token)[1..(token.loc.end - token.loc.start)]);
                                    try out_writer.writeAll("\"");
                                    try out_writer.writeAll(" ");
                                }
                                try out_writer.writeAll(data_toker.getTokenSlice(token));
                            },
                            .int_array, .float_array, .bool_array, .id_array => {
                                while (token.tag != .r_bracket) : (token = data_toker.next()) {
                                    try out_writer.writeAll(data_toker.getTokenSlice(token));
                                    try out_writer.writeAll(" ");
                                }
                                try out_writer.writeAll(data_toker.getTokenSlice(token));
                            },
                            else => try out_writer.writeAll(data_toker.getTokenSlice(token)), //write the value as if
                        }
                        try out_writer.writeAll(", ");
                    }
                }
                try out_writer.writeAll("}");
                try out_writer.writeAll(", ");
            }
        }
        // Write the end }
        try out_writer.writeAll("]");
    }

    fn isMemberNameInAdditionalData(_: *FileEngine, member_name: []const u8, additional_data: AdditionalData) bool {
        for (additional_data.member_to_find.items) |elem| {
            if (std.mem.eql(u8, member_name, elem.name)) return true;
        }
        return false;
    }

    /// Use a struct name to populate a list with all UUID of this struct
    pub fn getAllUUIDList(self: *FileEngine, struct_name: []const u8, uuid_array: *std.ArrayList(UUID)) !void {
        const max_file_index = try self.maxFileIndex(struct_name);
        var current_index: usize = 0;

        var path_buff = std.fmt.allocPrint(self.allocator, "{s}/DATA/{s}/{d}.zippondata", .{ self.path_to_ZipponDB_dir, struct_name, current_index }) catch @panic("Can't create sub_path for init a DataIterator");
        defer self.allocator.free(path_buff);

        var file = std.fs.cwd().openFile(path_buff, .{}) catch {
            std.debug.print("Path: {s}", .{path_buff});
            @panic("Can't open first file to init a data iterator");
        };
        defer file.close();

        var output: [1024 * 50]u8 = undefined; // Maybe need to increase that as it limit the size of a line in a file
        var output_fbs = std.io.fixedBufferStream(&output);
        const writer = output_fbs.writer();

        var buffered = std.io.bufferedReader(file.reader());
        var reader = buffered.reader();

        while (true) {
            output_fbs.reset();
            reader.streamUntilDelimiter(writer, '\n', null) catch |err| switch (err) {
                error.EndOfStream => {
                    // When end of file, check if all file was parse, if not update the reader to the next file
                    // TODO: Be able to give an array of file index from the B+Tree to only parse them
                    output_fbs.reset(); // clear buffer before exit

                    if (current_index == max_file_index) break;

                    current_index += 1;

                    self.allocator.free(path_buff);
                    path_buff = std.fmt.allocPrint(self.allocator, "{s}/DATA/{s}/{d}.zippondata", .{ self.path_to_ZipponDB_dir, struct_name, current_index }) catch @panic("Can't create sub_path for init a DataIterator");

                    file.close(); // Do I need to close ? I think so
                    file = std.fs.cwd().openFile(path_buff, .{}) catch {
                        std.debug.print("Error trying to open {s}\n", .{path_buff});
                        @panic("Can't open file to update a data iterator");
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

            const uuid = try UUID.parse(output_fbs.getWritten()[0..36]);
            try uuid_array.append(uuid);
        }
    }

    /// Take a condition and an array of UUID and fill the array with all UUID that match the condition
    /// TODO: Change the UUID function to be a B+Tree
    /// TODO: Optimize the shit out of this, it it way too slow rn. Here some ideas
    /// - Array can take a very long time to parse, maybe put them in a seperate file. But string can be too...
    /// - Use the stream directly in the tokenizer
    /// - Use a fixed size and split into other file. Like one file for one member (Because very long, like an array of 1000 value) and another one for everything else
    ///     The threselhold can be like if the average len is > 400 character. So UUID would take less that 10% of the storage
    /// - Save data in a more compact way
    /// - Multithreading, each thread take a list of files and we mix them at the end
    pub fn getUUIDListUsingCondition(self: *FileEngine, condition: Condition, uuid_array: *std.ArrayList(UUID)) !void {
        const max_file_index = try self.maxFileIndex(condition.struct_name);
        var current_index: usize = 0;

        var path_buff = std.fmt.allocPrint(self.allocator, "{s}/DATA/{s}/{d}.zippondata", .{ self.path_to_ZipponDB_dir, condition.struct_name, current_index }) catch @panic("Can't create sub_path for init a DataIterator");
        defer self.allocator.free(path_buff);

        var file = std.fs.cwd().openFile(path_buff, .{}) catch {
            std.debug.print("Path: {s}", .{path_buff});
            @panic("Can't open first file to init a data iterator");
        };
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
            .id => compare_value = ComparisonValue{ .id = try UUID.parse(condition.value) },
            .int_array => compare_value = ComparisonValue{ .int_array = parseArrayInt(self.allocator, condition.value) },
            .str_array => compare_value = ComparisonValue{ .str_array = parseArrayStr(self.allocator, condition.value) },
            .float_array => compare_value = ComparisonValue{ .float_array = parseArrayFloat(self.allocator, condition.value) },
            .bool_array => compare_value = ComparisonValue{ .bool_array = parseArrayBool(self.allocator, condition.value) },
            .id_array => compare_value = ComparisonValue{ .id_array = parseArrayUUID(self.allocator, condition.value) },
        }
        defer {
            switch (condition.data_type) {
                .int_array => compare_value.int_array.deinit(),
                .str_array => compare_value.str_array.deinit(),
                .float_array => compare_value.float_array.deinit(),
                .bool_array => compare_value.bool_array.deinit(),
                .id_array => compare_value.id_array.deinit(),
                else => {},
            }
        }

        var token: FileToken = undefined;
        const column_index = self.columnIndexOfMember(condition.struct_name, condition.member_name);

        while (true) {
            output_fbs.reset();
            reader.streamUntilDelimiter(writer, '\n', null) catch |err| switch (err) {
                error.EndOfStream => {
                    // When end of file, check if all file was parse, if not update the reader to the next file
                    // TODO: Be able to give an array of file index from the B+Tree to only parse them
                    output_fbs.reset(); // clear buffer before exit

                    if (current_index == max_file_index) break;

                    current_index += 1;

                    self.allocator.free(path_buff);
                    path_buff = std.fmt.allocPrint(self.allocator, "{s}/DATA/{s}/{d}.zippondata", .{ self.path_to_ZipponDB_dir, condition.struct_name, current_index }) catch @panic("Can't create sub_path for init a DataIterator");

                    file.close(); // Do I need to close ? I think so
                    file = std.fs.cwd().openFile(path_buff, .{}) catch {
                        std.debug.print("Error trying to open {s}\n", .{path_buff});
                        @panic("Can't open file to update a data iterator");
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

            var data_toker = FileTokenizer.init(null_terminated_string);
            const uuid = try UUID.parse(output_fbs.getWritten()[0..36]);

            // Skip unwanted token
            for (0..column_index.?) |_| {
                _ = data_toker.next();
            }

            token = data_toker.next();

            // TODO: Make sure in amount that the rest is unreachable by sending an error for wrong condition like superior between 2 string or array
            switch (condition.operation) {
                .equal => switch (condition.data_type) {
                    .int => if (compare_value.int == parseInt(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                    .float => if (compare_value.float == parseFloat(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                    .str => if (std.mem.eql(u8, compare_value.str, data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                    .bool => if (compare_value.bool_ == parseBool(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                    .id => if (compare_value.id.compare(uuid)) try uuid_array.append(uuid),
                    else => unreachable,
                },

                .different => switch (condition.data_type) {
                    .int => if (compare_value.int != parseInt(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                    .float => if (compare_value.float != parseFloat(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                    .str => if (!std.mem.eql(u8, compare_value.str, data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                    .bool => if (compare_value.bool_ != parseBool(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                    else => unreachable,
                },

                .superior_or_equal => switch (condition.data_type) {
                    .int => if (compare_value.int <= parseInt(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                    .float => if (compare_value.float <= parseFloat(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                    else => unreachable,
                },

                .superior => switch (condition.data_type) {
                    .int => if (compare_value.int < parseInt(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                    .float => if (compare_value.float < parseFloat(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                    else => unreachable,
                },

                .inferior_or_equal => switch (condition.data_type) {
                    .int => if (compare_value.int >= parseInt(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                    .float => if (compare_value.float >= parseFloat(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                    else => unreachable,
                },

                .inferior => switch (condition.data_type) {
                    .int => if (compare_value.int > parseInt(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                    .float => if (compare_value.float > parseFloat(data_toker.getTokenSlice(token))) try uuid_array.append(uuid),
                    else => unreachable,
                },

                // TODO: Do it for other array and implement in the query language
                .in => switch (condition.data_type) {
                    .id_array => {
                        for (compare_value.id_array.items) |elem| {
                            if (elem.compare(uuid)) try uuid_array.append(uuid);
                        }
                    },
                    else => unreachable,
                },
            }
        }
    }

    // TODO: Clean a bit the code
    // Do I need multiple files too ? I mean it duplicate UUID a lot, if it's just to save a name like 'Bob', storing a long UUID is overkill
    // I could just use a tabular data format with separator using space - Or maybe I encode the uuid to take a minimum space as I always know it size
    pub fn writeEntity(self: *FileEngine, struct_name: []const u8, data_map: std.StringHashMap([]const u8)) !UUID {
        const uuid = UUID.init();

        const potential_file_index = try self.getFirstUsableIndexFile(struct_name);
        var file: std.fs.File = undefined;
        defer file.close();

        var path: []const u8 = undefined;
        defer self.allocator.free(path);

        if (potential_file_index) |file_index| {
            path = try std.fmt.allocPrint(self.allocator, "{s}/DATA/{s}/{d}.zippondata", .{ self.path_to_ZipponDB_dir, struct_name, file_index });
            file = std.fs.cwd().openFile(path, .{ .mode = .read_write }) catch @panic("=(");
        } else {
            const max_index = try self.maxFileIndex(struct_name);

            path = try std.fmt.allocPrint(self.allocator, "{s}/DATA/{s}/{d}.zippondata", .{ self.path_to_ZipponDB_dir, struct_name, max_index + 1 });
            file = std.fs.cwd().createFile(path, .{}) catch @panic("Error creating new data file");
        }

        try file.seekFromEnd(0);
        try file.writer().print("{s}", .{uuid.format_uuid()});

        for (self.structName2structMembers(struct_name)) |member_name| {
            try file.writer().print(" {s}", .{data_map.get(self.locToSlice(member_name)).?});
        }

        try file.writer().print("\n", .{});

        return uuid;
    }

    /// Function to update the file with updated data. Take a list of uuid and a list of string map. The map is in the format key: member; value: new value.
    /// It create a new index.zippondata.new file in the same folder, stream the output of the old file to it until a uuid is found, then write the new row and continue until the end
    /// TODO: Optmize a lot, I did that quickly to work but it is far from optimized. Idea:
    ///     - Once all uuid found, stream until the end of the file without delimiter or uuid compare
    ///     - Change map to array
    pub fn updateEntities(self: *FileEngine, struct_name: []const u8, uuids: []UUID, new_data_map: std.StringHashMap([]const u8)) !void {
        const max_file_index = self.maxFileIndex(struct_name) catch @panic("Cant get max index file when updating");
        var current_file_index: usize = 0;

        var path_buff = std.fmt.allocPrint(self.allocator, "{s}/DATA/{s}/{d}.zippondata", .{ self.path_to_ZipponDB_dir, struct_name, current_file_index }) catch @panic("Can't create sub_path for init a DataIterator");
        defer self.allocator.free(path_buff);

        var path_buff2 = std.fmt.allocPrint(self.allocator, "{s}/DATA/{s}/{d}.zippondata", .{ self.path_to_ZipponDB_dir, struct_name, current_file_index }) catch @panic("Can't create sub_path for init a DataIterator");
        defer self.allocator.free(path_buff2);

        var old_file = std.fs.cwd().openFile(path_buff, .{}) catch {
            std.debug.print("Path: {s}", .{path_buff});
            @panic("Can't open first file to init a data iterator");
        };

        self.allocator.free(path_buff);
        path_buff = std.fmt.allocPrint(self.allocator, "{s}/DATA/{s}/{d}.zippondata.new", .{ self.path_to_ZipponDB_dir, struct_name, current_file_index }) catch @panic("Can't create sub_path for init a DataIterator");

        var new_file = std.fs.cwd().createFile(path_buff, .{}) catch {
            std.debug.print("Path: {s}", .{path_buff});
            @panic("Can't create new file to init a data iterator");
        };
        defer new_file.close();

        var output: [1024 * 50]u8 = undefined; // Maybe need to increase that as it limit the size of a line in a file
        var output_fbs = std.io.fixedBufferStream(&output);
        const writer = output_fbs.writer();

        var buffered = std.io.bufferedReader(old_file.reader());
        var reader = buffered.reader();
        var founded = false;

        while (true) {
            output_fbs.reset();
            reader.streamUntilDelimiter(writer, ' ', null) catch |err| switch (err) {
                error.EndOfStream => {
                    // When end of file, check if all file was parse, if not update the reader to the next file
                    // TODO: Be able to give an array of file index from the B+Tree to only parse them
                    output_fbs.reset(); // clear buffer before exit

                    // Start by deleting and renaming the new file
                    self.allocator.free(path_buff);
                    path_buff = std.fmt.allocPrint(self.allocator, "{s}/DATA/{s}/{d}.zippondata", .{ self.path_to_ZipponDB_dir, struct_name, current_file_index }) catch @panic("Can't create sub_path for init a DataIterator");

                    self.allocator.free(path_buff2);
                    path_buff2 = std.fmt.allocPrint(self.allocator, "{s}/DATA/{s}/{d}.zippondata.new", .{ self.path_to_ZipponDB_dir, struct_name, current_file_index }) catch @panic("Can't create sub_path for init a DataIterator");

                    old_file.close();
                    try std.fs.cwd().deleteFile(path_buff);
                    try std.fs.cwd().rename(path_buff2, path_buff);

                    if (current_file_index == max_file_index) break;

                    current_file_index += 1;

                    self.allocator.free(path_buff);
                    path_buff = std.fmt.allocPrint(self.allocator, "{s}/DATA/{s}/{d}.zippondata", .{ self.path_to_ZipponDB_dir, struct_name, current_file_index }) catch @panic("Can't create sub_path for init a DataIterator");

                    self.allocator.free(path_buff2);
                    path_buff2 = std.fmt.allocPrint(self.allocator, "{s}/DATA/{s}/{d}.zippondata.new", .{ self.path_to_ZipponDB_dir, struct_name, current_file_index }) catch @panic("Can't create sub_path for init a DataIterator");

                    old_file = std.fs.cwd().openFile(path_buff, .{}) catch {
                        std.debug.print("Error trying to open {s}\n", .{path_buff});
                        @panic("Can't open  file to update entities");
                    };

                    new_file = std.fs.cwd().createFile(path_buff2, .{}) catch {
                        std.debug.print("Error trying to create {s}\n", .{path_buff2});
                        @panic("Can't create  file to update entities");
                    };

                    buffered = std.io.bufferedReader(old_file.reader());
                    reader = buffered.reader();
                    continue;
                }, // file read till the end
                else => {
                    std.debug.print("Error while reading file: {any}\n", .{err});
                    break;
                },
            };

            try new_file.writeAll(output_fbs.getWritten());

            // THis is the uuid of the current row
            const uuid = try UUID.parse(output_fbs.getWritten()[0..36]);
            founded = false;

            // Optimize this
            for (uuids) |elem| {
                if (elem.compare(uuid)) {
                    founded = true;
                    break;
                }
            }

            if (founded) {
                for (self.structName2structMembers(struct_name), self.structName2DataType(struct_name)) |member_name, member_type| {
                    // For all collum in the right order, check if the key is in the map, if so use it to write the new value, otherwise use the old file
                    output_fbs.reset();
                    switch (member_type) {
                        .str => {
                            try reader.streamUntilDelimiter(writer, '\'', null);
                            try reader.streamUntilDelimiter(writer, '\'', null);
                        },
                        .int_array, .float_array, .bool_array, .id_array => try reader.streamUntilDelimiter(writer, ']', null),
                        .str_array => try reader.streamUntilDelimiter(writer, ']', null), // FIXME: If the string itself contain ], this will be a problem
                        else => {
                            try reader.streamUntilDelimiter(writer, ' ', null);
                            try reader.streamUntilDelimiter(writer, ' ', null);
                        },
                    }

                    if (new_data_map.contains(self.locToSlice(member_name))) {
                        // Write the new data
                        try new_file.writer().print(" {s}", .{new_data_map.get(self.locToSlice(member_name)).?});
                    } else {
                        // Write the old data
                        switch (member_type) {
                            .str => try new_file.writeAll(" \'"),
                            .int_array => try new_file.writeAll(" "),
                            .float_array => try new_file.writeAll(" "),
                            .str_array => try new_file.writeAll(" "),
                            .bool_array => try new_file.writeAll(" "),
                            .id_array => try new_file.writeAll(" "),
                            else => try new_file.writeAll(" "),
                        }

                        try new_file.writeAll(output_fbs.getWritten());

                        switch (member_type) {
                            .str => try new_file.writeAll("\'"),
                            .int_array, .float_array, .bool_array, .id_array => try new_file.writeAll("]"),
                            else => {},
                        }
                    }
                }

                try reader.streamUntilDelimiter(writer, '\n', null);
                try new_file.writeAll("\n");
            } else {
                // stream until the delimiter
                output_fbs.reset();
                try new_file.writeAll(" ");
                try reader.streamUntilDelimiter(writer, '\n', null);
                try new_file.writeAll(output_fbs.getWritten());
                try new_file.writeAll("\n");
            }
        }
    }

    /// Take a kist of UUID and a struct name and delete the row with same UUID
    /// TODO: Use B+Tree
    pub fn deleteEntities(self: *FileEngine, struct_name: []const u8, uuids: []UUID) !usize {
        const max_file_index = self.maxFileIndex(struct_name) catch @panic("Cant get max index file when updating");
        var current_file_index: usize = 0;

        var path_buff = std.fmt.allocPrint(self.allocator, "{s}/DATA/{s}/{d}.zippondata", .{ self.path_to_ZipponDB_dir, struct_name, current_file_index }) catch @panic("Can't create sub_path for init a DataIterator");
        defer self.allocator.free(path_buff);

        var path_buff2 = std.fmt.allocPrint(self.allocator, "{s}/DATA/{s}/{d}.zippondata", .{ self.path_to_ZipponDB_dir, struct_name, current_file_index }) catch @panic("Can't create sub_path for init a DataIterator");
        defer self.allocator.free(path_buff2);

        var old_file = std.fs.cwd().openFile(path_buff, .{}) catch {
            std.debug.print("Path: {s}", .{path_buff});
            @panic("Can't open first file to init a data iterator");
        };

        self.allocator.free(path_buff);
        path_buff = std.fmt.allocPrint(self.allocator, "{s}/DATA/{s}/{d}.zippondata.new", .{ self.path_to_ZipponDB_dir, struct_name, current_file_index }) catch @panic("Can't create sub_path for init a DataIterator");

        var new_file = std.fs.cwd().createFile(path_buff, .{}) catch {
            std.debug.print("Path: {s}", .{path_buff});
            @panic("Can't create new file to init a data iterator");
        };
        defer new_file.close();

        var output: [1024 * 50]u8 = undefined; // Maybe need to increase that as it limit the size of a line in a file
        var output_fbs = std.io.fixedBufferStream(&output);
        const writer = output_fbs.writer();

        var buffered = std.io.bufferedReader(old_file.reader());
        var reader = buffered.reader();
        var founded = false;
        var deleted_count: usize = 0;

        while (true) {
            output_fbs.reset();
            reader.streamUntilDelimiter(writer, ' ', null) catch |err| switch (err) {
                error.EndOfStream => {
                    // When end of file, check if all file was parse, if not update the reader to the next file
                    // TODO: Be able to give an array of file index from the B+Tree to only parse them
                    output_fbs.reset(); // clear buffer before exit

                    // Start by deleting and renaming the new file
                    self.allocator.free(path_buff);
                    path_buff = std.fmt.allocPrint(self.allocator, "{s}/DATA/{s}/{d}.zippondata", .{ self.path_to_ZipponDB_dir, struct_name, current_file_index }) catch @panic("Can't create sub_path for init a DataIterator");

                    self.allocator.free(path_buff2);
                    path_buff2 = std.fmt.allocPrint(self.allocator, "{s}/DATA/{s}/{d}.zippondata.new", .{ self.path_to_ZipponDB_dir, struct_name, current_file_index }) catch @panic("Can't create sub_path for init a DataIterator");

                    old_file.close();
                    try std.fs.cwd().deleteFile(path_buff);
                    try std.fs.cwd().rename(path_buff2, path_buff);

                    if (current_file_index == max_file_index) break;

                    current_file_index += 1;

                    self.allocator.free(path_buff);
                    path_buff = std.fmt.allocPrint(self.allocator, "{s}/DATA/{s}/{d}.zippondata", .{ self.path_to_ZipponDB_dir, struct_name, current_file_index }) catch @panic("Can't create sub_path for init a DataIterator");

                    self.allocator.free(path_buff2);
                    path_buff2 = std.fmt.allocPrint(self.allocator, "{s}/DATA/{s}/{d}.zippondata.new", .{ self.path_to_ZipponDB_dir, struct_name, current_file_index }) catch @panic("Can't create sub_path for init a DataIterator");

                    old_file = std.fs.cwd().openFile(path_buff, .{}) catch {
                        std.debug.print("Error trying to open {s}\n", .{path_buff});
                        @panic("Can't open  file to update entities");
                    };

                    new_file = std.fs.cwd().createFile(path_buff2, .{}) catch {
                        std.debug.print("Error trying to create {s}\n", .{path_buff2});
                        @panic("Can't create  file to update entities");
                    };

                    buffered = std.io.bufferedReader(old_file.reader());
                    reader = buffered.reader();
                    continue;
                }, // file read till the end
                else => {
                    std.debug.print("Error while reading file: {any}\n", .{err});
                    break;
                },
            };

            // THis is the uuid of the current row
            const uuid = try UUID.parse(output_fbs.getWritten()[0..36]);
            founded = false;

            // Optimize this
            for (uuids) |elem| {
                if (elem.compare(uuid)) {
                    founded = true;
                    deleted_count += 1;
                    break;
                }
            }

            if (!founded) {
                // stream until the delimiter
                try new_file.writeAll(output_fbs.getWritten());

                output_fbs.reset();
                try new_file.writeAll(" ");
                try reader.streamUntilDelimiter(writer, '\n', null);
                try new_file.writeAll(output_fbs.getWritten());
                try new_file.writeAll("\n");
            } else {
                try reader.streamUntilDelimiter(writer, '\n', null);
            }
        }

        return deleted_count;
    }

    /// Use a filename in the format 1.zippondata and return the 1
    /// Note that if I change the extension of the data file, I need to update that as it use a fixed len for the extension
    fn fileName2Index(_: FileEngine, file_name: []const u8) usize {
        return std.fmt.parseInt(usize, file_name[0..(file_name.len - 11)], 10) catch @panic("Couln't parse the int of a zippondata file.");
    }

    /// Use the map of file stat to find the first file with under the bytes limit.
    /// return the name of the file. If none is found, return null.
    fn getFirstUsableIndexFile(self: FileEngine, struct_name: []const u8) !?usize {
        const path = try std.fmt.allocPrint(self.allocator, "{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, struct_name });
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
        const path = try std.fmt.allocPrint(self.allocator, "{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, struct_name });
        defer self.allocator.free(path);

        const member_dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
        var count: usize = 0;

        var iter = member_dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;
            count += 1;
        }
        return count - 1;
    }

    pub fn writeDbMetrics(self: *FileEngine, buffer: *std.ArrayList(u8)) !void {
        const path = try std.fmt.allocPrint(self.allocator, "{s}", .{self.path_to_ZipponDB_dir});
        defer self.allocator.free(path);

        const main_dir = try std.fs.cwd().openDir(path, .{ .iterate = true });

        const writer = buffer.writer();
        try writer.print("Database path: {s}\n", .{path});
        const main_size = try self.getDirTotalSize(main_dir);
        try writer.print("Total size: {d:.2}Mb\n", .{@as(f64, @floatFromInt(main_size)) / 1e6});

        const log_dir = try main_dir.openDir("LOG", .{ .iterate = true });
        const log_size = try self.getDirTotalSize(log_dir);
        try writer.print("LOG: {d:.2}Mb\n", .{@as(f64, @floatFromInt(log_size)) / 1e6});

        const backup_dir = try main_dir.openDir("BACKUP", .{ .iterate = true });
        const backup_size = try self.getDirTotalSize(backup_dir);
        try writer.print("BACKUP: {d:.2}Mb\n", .{@as(f64, @floatFromInt(backup_size)) / 1e6});

        const data_dir = try main_dir.openDir("DATA", .{ .iterate = true });
        const data_size = try self.getDirTotalSize(data_dir);
        try writer.print("DATA: {d:.2}Mb\n", .{@as(f64, @floatFromInt(data_size)) / 1e6});

        var iter = data_dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .directory) continue;
            const sub_dir = try data_dir.openDir(entry.name, .{ .iterate = true });
            const size = try self.getDirTotalSize(sub_dir);
            try writer.print("  {s}: {d:.}Mb\n", .{ entry.name, @as(f64, @floatFromInt(size)) / 1e6 });
        }
    }

    // Maybe make it so it use itself to search if it find a directory
    fn getDirTotalSize(self: FileEngine, dir: std.fs.Dir) !u64 {
        var total: u64 = 0;
        var stat: std.fs.File.Stat = undefined;
        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .directory) {
                const sub_dir = try dir.openDir(entry.name, .{ .iterate = true });
                total += try self.getDirTotalSize(sub_dir);
            }

            if (entry.kind != .file) continue;
            stat = try dir.statFile(entry.name);
            total += stat.size;
        }
        return total;
    }

    const FileError = error{
        SchemaFileNotFound,
        SchemaNotConform,
        DATAFolderNotFound,
        StructFolderNotFound,
        CantMakeDir,
        CantMakeFile,
    };

    /// Request a path to a schema file and then create the struct folder
    /// TODO: Check if some data already exist and if so ask if the user want to delete it and make a backup
    pub fn initDataFolder(self: *FileEngine, path_to_schema_file: []const u8) FileError!void {
        var schema_buf = self.allocator.alloc(u8, 1024 * 50) catch @panic("Cant allocate the schema buffer");
        defer self.allocator.free(schema_buf);

        const file = std.fs.cwd().openFile(path_to_schema_file, .{}) catch return FileError.SchemaFileNotFound;
        defer file.close();

        const len = file.readAll(schema_buf) catch @panic("Can't read schema file");

        self.allocator.free(self.null_terminated_schema_buff);
        self.null_terminated_schema_buff = self.allocator.dupeZ(u8, schema_buf[0..len]) catch @panic("Cant allocate null term buffer for the schema");

        var toker = SchemaTokenizer.init(self.null_terminated_schema_buff);
        var parser = SchemaParser.init(&toker, self.allocator);

        // Deinit the struct array before creating a new one
        for (self.struct_array.items) |*elem| elem.deinit();
        for (0..self.struct_array.items.len) |_| _ = self.struct_array.pop();

        parser.parse(&self.struct_array) catch return error.SchemaNotConform;

        const path = std.fmt.allocPrint(self.allocator, "{s}/DATA", .{self.path_to_ZipponDB_dir}) catch @panic("Cant allocate path");
        defer self.allocator.free(path);

        var data_dir = std.fs.cwd().openDir(path, .{}) catch return FileError.DATAFolderNotFound;
        defer data_dir.close();

        for (self.struct_array.items) |struct_item| {
            data_dir.makeDir(self.locToSlice(struct_item.name)) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return FileError.CantMakeDir,
            };
            const struct_dir = data_dir.openDir(self.locToSlice(struct_item.name), .{}) catch return FileError.StructFolderNotFound;

            _ = struct_dir.createFile("0.zippondata", .{}) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return FileError.CantMakeFile,
            };
        }

        self.writeSchemaFile();
    }

    // Stuff for schema

    pub fn readSchemaFile(allocator: Allocator, sub_path: []const u8, buffer: []u8) !usize {
        const path = try std.fmt.allocPrint(allocator, "{s}/schema.zipponschema", .{sub_path});
        defer allocator.free(path);

        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const len = try file.readAll(buffer);
        return len;
    }

    pub fn writeSchemaFile(self: *FileEngine) void {
        // Delete the current schema file
        // Create a new one
        // Dumpe the buffer inside
        var zippon_dir = std.fs.cwd().openDir(self.path_to_ZipponDB_dir, .{}) catch @panic("Cant open main folder!");
        defer zippon_dir.close();
        zippon_dir.deleteFile("schema.zipponschema") catch |err| switch (err) {
            error.FileNotFound => {},
            else => @panic("Error other than file not found when writing the schema."),
        };

        var file = zippon_dir.createFile("schema.zipponschema", .{}) catch @panic("Can't create new schema file");
        defer file.close();
        file.writeAll(self.null_terminated_schema_buff) catch @panic("Can't write new schema");
    }

    pub fn locToSlice(self: *FileEngine, loc: SchemaToken.Loc) []const u8 {
        return self.null_terminated_schema_buff[loc.start..loc.end];
    }

    pub fn columnIndexOfMember(self: *FileEngine, struct_name: []const u8, member_name: []const u8) ?usize {
        var i: u16 = 0;

        for (self.structName2structMembers(struct_name)) |mn| {
            if (std.mem.eql(u8, self.locToSlice(mn), member_name)) return i;
            i += 1;
        }

        return null;
    }

    /// Get the type of the member
    pub fn memberName2DataType(self: *FileEngine, struct_name: []const u8, member_name: []const u8) ?DataType {
        var i: u16 = 0;

        for (self.structName2structMembers(struct_name)) |mn| {
            if (std.mem.eql(u8, self.locToSlice(mn), member_name)) return self.structName2DataType(struct_name)[i];
            i += 1;
        }

        return null;
    }

    /// Get the list of all member name for a struct name
    pub fn structName2structMembers(self: *FileEngine, struct_name: []const u8) []SchemaToken.Loc {
        var i: u16 = 0;

        while (i < self.struct_array.items.len) : (i += 1) if (std.mem.eql(u8, self.locToSlice(self.struct_array.items[i].name), struct_name)) break;

        if (i == self.struct_array.items.len) {
            @panic("Struct name not found!");
        }

        return self.struct_array.items[i].members.items;
    }

    pub fn structName2DataType(self: *FileEngine, struct_name: []const u8) []const DataType {
        var i: u16 = 0;

        while (i < self.struct_array.items.len) : (i += 1) if (std.mem.eql(u8, self.locToSlice(self.struct_array.items[i].name), struct_name)) break;

        return self.struct_array.items[i].types.items;
    }

    /// Chech if the name of a struct is in the current schema
    pub fn isStructNameExists(self: *FileEngine, struct_name: []const u8) bool {
        var i: u16 = 0;
        while (i < self.struct_array.items.len) : (i += 1) if (std.mem.eql(u8, self.locToSlice(self.struct_array.items[i].name), struct_name)) return true;
        return false;
    }

    /// Check if a struct have the member name
    pub fn isMemberNameInStruct(self: *FileEngine, struct_name: []const u8, member_name: []const u8) bool {
        for (self.structName2structMembers(struct_name)) |mn| {
            if (std.mem.eql(u8, self.locToSlice(mn), member_name)) return true;
        }
        return false;
    }

    /// Check if a string is a name of a struct in the currently use engine
    pub fn isStructInSchema(self: *FileEngine, struct_name_to_check: []const u8) bool {
        for (self.struct_array.items) |struct_schema| {
            if (std.mem.eql(u8, struct_name_to_check, struct_schema.name)) {
                return true;
            }
        }
        return false;
    }

    // Return true if the map have all the member name as key and not more
    pub fn checkIfAllMemberInMap(self: *FileEngine, struct_name: []const u8, map: *std.StringHashMap([]const u8)) bool {
        const all_struct_member = self.structName2structMembers(struct_name);
        var count: u16 = 0;

        for (all_struct_member) |mn| {
            if (map.contains(self.locToSlice(mn))) count += 1 else std.debug.print("Missing: {s}\n", .{self.locToSlice(mn)});
        }

        return ((count == all_struct_member.len) and (count == map.count()));
    }
};

test "Get list of UUID using condition" {
    const allocator = std.testing.allocator;

    const path = try allocator.dupe(u8, "ZipponDB");
    var file_engine = FileEngine.init(allocator, path);
    defer file_engine.deinit();

    var uuid_array = std.ArrayList(UUID).init(allocator);
    defer uuid_array.deinit();

    const condition = FileEngine.Condition{ .struct_name = "User", .member_name = "email", .value = "adrien@mail.com", .operation = .equal, .data_type = .str };
    try file_engine.getUUIDListUsingCondition(condition, &uuid_array);
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

pub fn parseArrayUUID(allocator: std.mem.Allocator, array_str: []const u8) std.ArrayList(UUID) {
    var array = std.ArrayList(UUID).init(allocator);

    var it = std.mem.splitAny(u8, array_str[1 .. array_str.len - 1], " ");
    while (it.next()) |x| {
        const uuid = UUID.parse(x) catch continue;
        array.append(uuid) catch continue;
    }

    return array;
}

// FIXME: I think it will not work if there is a ' inside the string
pub fn parseArrayStr(allocator: std.mem.Allocator, array_str: []const u8) std.ArrayList([]const u8) {
    var array = std.ArrayList([]const u8).init(allocator);

    var it = std.mem.splitAny(u8, array_str[1 .. array_str.len - 1], "'");
    while (it.next()) |x| {
        if (std.mem.eql(u8, " ", x)) continue;
        const x_copy = allocator.dupe(u8, x) catch @panic("=(");
        // FIXME: I think I need to add the '' on each side again
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
