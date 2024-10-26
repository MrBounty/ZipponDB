const std = @import("std");
const utils = @import("stuffs/utils.zig");
const s2t = @import("types/stringToType.zig");
const zid = @import("ZipponData");
const Allocator = std.mem.Allocator;

// TODO: Clean that
const UUID = @import("types/uuid.zig").UUID;
const DateTime = @import("types/date.zig").DateTime;
const DataType = @import("types/dataType.zig").DataType;
const FileTokenizer = @import("tokenizers/file.zig").Tokenizer;
const FileToken = @import("tokenizers/file.zig").Token;
const SchemaStruct = @import("schemaParser.zig").Parser.SchemaStruct;
const SchemaParser = @import("schemaParser.zig").Parser;
const SchemaTokenizer = @import("tokenizers/schema.zig").Tokenizer;
const SchemaToken = @import("tokenizers/schema.zig").Token;
const AdditionalData = @import("stuffs/additionalData.zig").AdditionalData;
const Loc = @import("tokenizers/shared/loc.zig").Loc;

const FileEngineError = @import("stuffs/errors.zig").FileEngineError;

const BUFFER_SIZE = @import("config.zig").BUFFER_SIZE;
const MAX_FILE_SIZE = @import("config.zig").MAX_FILE_SIZE;
const CSV_DELIMITER = @import("config.zig").CSV_DELIMITER;

const log = std.log.scoped(.fileEngine);

/// Manage everything that is relate to read or write in files
/// Or even get stats, whatever. If it touch files, it's here
pub const FileEngine = struct {
    allocator: Allocator,
    path_to_ZipponDB_dir: []const u8,
    null_terminated_schema_buff: [:0]u8,
    struct_array: std.ArrayList(SchemaStruct),

    // TODO: Check is all DATA folder are ok. Meaning there is all struct dir, at least one zippon file and all file are 0.zippondata or csv later
    pub fn init(allocator: Allocator, path: []const u8) FileEngine {
        const path_to_ZipponDB_dir = path;

        var schema_buf = allocator.alloc(u8, BUFFER_SIZE) catch @panic("Cant allocate the schema buffer");
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
        };
    }

    pub fn deinit(self: *FileEngine) void {
        if (self.struct_array.items.len > 0) {
            for (self.struct_array.items) |*elem| elem.deinit();
        }
        self.struct_array.deinit();
        self.allocator.free(self.null_terminated_schema_buff);
        self.allocator.free(self.path_to_ZipponDB_dir);
    }

    pub fn usable(self: FileEngine) bool {
        return !std.mem.eql(u8, "", self.path_to_ZipponDB_dir);
    }

    const ComparisonValue = union {
        int: i64,
        float: f64,
        str: []const u8,
        bool_: bool,
        link: UUID,
        datetime: DateTime,
        int_array: std.ArrayList(i64),
        str_array: std.ArrayList([]const u8),
        float_array: std.ArrayList(f64),
        bool_array: std.ArrayList(bool),
        link_array: std.ArrayList(UUID),
        datetime_array: std.ArrayList(DateTime),
    };

    /// use to parse file. It take a struct name and member name to know what to parse.
    /// An Operation from equal, different, superior, superior_or_equal, ...
    /// The DataType from int, float and str
    /// TODO: Use token from the query for struct_name, member_name and value, to save memory
    /// TODO: Update to do multiple operation at the same tome on a row
    pub const Condition = struct {
        struct_name: []const u8,
        member_name: []const u8 = undefined,
        value: []const u8 = undefined,
        operation: enum { equal, different, superior, superior_or_equal, inferior, inferior_or_equal, in } = undefined,
        data_type: DataType = undefined,

        pub fn init(struct_loc: []const u8) Condition {
            return Condition{ .struct_name = struct_loc };
        }
    };

    // --------------------Other--------------------

    pub fn readSchemaFile(allocator: Allocator, sub_path: []const u8, buffer: []u8) FileEngineError!usize {
        const path = std.fmt.allocPrint(allocator, "{s}/schema.zipponschema", .{sub_path}) catch return FileEngineError.MemoryError;
        defer allocator.free(path);

        const file = std.fs.cwd().openFile(path, .{}) catch return FileEngineError.CantOpenFile;
        defer file.close();

        const len = file.readAll(buffer) catch return FileEngineError.ReadError;
        return len;
    }

    pub fn writeDbMetrics(self: *FileEngine, buffer: *std.ArrayList(u8)) FileEngineError!void {
        const path = std.fmt.allocPrint(self.allocator, "{s}", .{self.path_to_ZipponDB_dir}) catch return FileEngineError.MemoryError;
        defer self.allocator.free(path);

        const main_dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return FileEngineError.CantOpenDir;

        const writer = buffer.writer();
        writer.print("Database path: {s}\n", .{path}) catch return FileEngineError.WriteError;
        const main_size = utils.getDirTotalSize(main_dir) catch 0;
        writer.print("Total size: {d:.2}Mb\n", .{@as(f64, @floatFromInt(main_size)) / 1e6}) catch return FileEngineError.WriteError;

        const log_dir = main_dir.openDir("LOG", .{ .iterate = true }) catch return FileEngineError.CantOpenDir;
        const log_size = utils.getDirTotalSize(log_dir) catch 0;
        writer.print("LOG: {d:.2}Mb\n", .{@as(f64, @floatFromInt(log_size)) / 1e6}) catch return FileEngineError.WriteError;

        const backup_dir = main_dir.openDir("BACKUP", .{ .iterate = true }) catch return FileEngineError.CantOpenDir;
        const backup_size = utils.getDirTotalSize(backup_dir) catch 0;
        writer.print("BACKUP: {d:.2}Mb\n", .{@as(f64, @floatFromInt(backup_size)) / 1e6}) catch return FileEngineError.WriteError;

        const data_dir = main_dir.openDir("DATA", .{ .iterate = true }) catch return FileEngineError.CantOpenDir;
        const data_size = utils.getDirTotalSize(data_dir) catch 0;
        writer.print("DATA: {d:.2}Mb\n", .{@as(f64, @floatFromInt(data_size)) / 1e6}) catch return FileEngineError.WriteError;

        var iter = data_dir.iterate();
        while (iter.next() catch return FileEngineError.DirIterError) |entry| {
            if (entry.kind != .directory) continue;
            const sub_dir = data_dir.openDir(entry.name, .{ .iterate = true }) catch return FileEngineError.CantOpenDir;
            const size = utils.getDirTotalSize(sub_dir) catch 0;
            writer.print("  {s}: {d:.}Mb\n", .{ entry.name, @as(f64, @floatFromInt(size)) / 1e6 }) catch return FileEngineError.WriteError;
        }
    }

    // --------------------Init folder and files--------------------

    /// Create the main folder. Including DATA, LOG and BACKUP
    pub fn checkAndCreateDirectories(self: *FileEngine) FileEngineError!void {
        var path_buff = std.fmt.allocPrint(self.allocator, "{s}", .{self.path_to_ZipponDB_dir}) catch return FileEngineError.MemoryError;
        defer self.allocator.free(path_buff);

        const cwd = std.fs.cwd();

        cwd.makeDir(path_buff) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return FileEngineError.CantMakeDir,
        };

        self.allocator.free(path_buff);
        path_buff = std.fmt.allocPrint(self.allocator, "{s}/DATA", .{self.path_to_ZipponDB_dir}) catch return FileEngineError.MemoryError;

        cwd.makeDir(path_buff) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return FileEngineError.CantMakeDir,
        };

        self.allocator.free(path_buff);
        path_buff = std.fmt.allocPrint(self.allocator, "{s}/BACKUP", .{self.path_to_ZipponDB_dir}) catch return FileEngineError.MemoryError;

        cwd.makeDir(path_buff) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return FileEngineError.CantMakeDir,
        };

        self.allocator.free(path_buff);
        path_buff = std.fmt.allocPrint(self.allocator, "{s}/LOG", .{self.path_to_ZipponDB_dir}) catch return FileEngineError.MemoryError;

        cwd.makeDir(path_buff) catch |err| switch (err) {
            error.PathAlreadyExists => return,
            else => return FileEngineError.CantMakeDir,
        };

        self.allocator.free(path_buff);
        path_buff = std.fmt.allocPrint(self.allocator, "{s}/LOG/log", .{self.path_to_ZipponDB_dir}) catch return FileEngineError.MemoryError;

        _ = cwd.createFile(path_buff, .{}) catch return FileEngineError.CantMakeFile;
    }

    /// Request a path to a schema file and then create the struct folder
    /// TODO: Check if some data already exist and if so ask if the user want to delete it and make a backup
    pub fn initDataFolder(self: *FileEngine, path_to_schema_file: []const u8) FileEngineError!void {
        var schema_buf = self.allocator.alloc(u8, BUFFER_SIZE) catch return FileEngineError.MemoryError;
        defer self.allocator.free(schema_buf);

        const file = std.fs.cwd().openFile(path_to_schema_file, .{}) catch return FileEngineError.SchemaFileNotFound;
        defer file.close();

        const len = file.readAll(schema_buf) catch return FileEngineError.ReadError;

        self.allocator.free(self.null_terminated_schema_buff);
        self.null_terminated_schema_buff = self.allocator.dupeZ(u8, schema_buf[0..len]) catch return FileEngineError.MemoryError;

        var toker = SchemaTokenizer.init(self.null_terminated_schema_buff);
        var parser = SchemaParser.init(&toker, self.allocator);

        // Deinit the struct array before creating a new one
        for (self.struct_array.items) |*elem| elem.deinit();
        for (0..self.struct_array.items.len) |_| _ = self.struct_array.pop();

        parser.parse(&self.struct_array) catch return error.SchemaNotConform;

        const path = std.fmt.allocPrint(self.allocator, "{s}/DATA", .{self.path_to_ZipponDB_dir}) catch return FileEngineError.MemoryError;
        defer self.allocator.free(path);

        var data_dir = std.fs.cwd().openDir(path, .{}) catch return FileEngineError.CantOpenDir;
        defer data_dir.close();

        for (self.struct_array.items) |schema_struct| {
            data_dir.makeDir(schema_struct.name) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return FileEngineError.CantMakeDir,
            };
            const struct_dir = data_dir.openDir(schema_struct.name, .{}) catch return FileEngineError.CantOpenDir;

            _ = struct_dir.createFile("0.csv", .{}) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return FileEngineError.CantMakeFile,
            };
        }

        try self.writeSchemaFile();
    }

    // --------------------Read and parse files--------------------

    /// Take a list of UUID and, a buffer array and the additional data to write into the buffer the JSON to send
    /// TODO: Optimize
    /// FIXME: Array of string are not working
    pub fn parseAndWriteToSend(self: *FileEngine, struct_name: []const u8, uuids: []UUID, buffer: *std.ArrayList(u8), additional_data: AdditionalData) FileEngineError!void {
        const max_file_index = try self.maxFileIndex(struct_name);
        var current_index: usize = 0;

        var path_buff = std.fmt.allocPrint(
            self.allocator,
            "{s}/DATA/{s}/{d}.csv",
            .{ self.path_to_ZipponDB_dir, struct_name, current_index },
        ) catch return FileEngineError.MemoryError;
        defer self.allocator.free(path_buff);

        var file = std.fs.cwd().openFile(path_buff, .{}) catch return FileEngineError.CantOpenFile;
        defer file.close();

        var output: [BUFFER_SIZE]u8 = undefined;
        var output_fbs = std.io.fixedBufferStream(&output);
        const writer = output_fbs.writer();

        var buffered = std.io.bufferedReader(file.reader());
        var reader = buffered.reader();
        var founded = false;
        var token: FileToken = undefined;

        var out_writer = buffer.writer();
        out_writer.writeAll("[") catch return FileEngineError.WriteError;

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
                    path_buff = std.fmt.allocPrint(
                        self.allocator,
                        "{s}/DATA/{s}/{d}.csv",
                        .{ self.path_to_ZipponDB_dir, struct_name, current_index },
                    ) catch @panic("Can't create sub_path for init a DataIterator");

                    file.close(); // Do I need to close ? I think so
                    file = std.fs.cwd().openFile(path_buff, .{}) catch {
                        log.err("Error trying to open {s}\n", .{path_buff});
                        @panic("Can't open file to update a data iterator");
                    };

                    buffered = std.io.bufferedReader(file.reader());
                    reader = buffered.reader();
                    continue;
                }, // file read till the end
                else => return FileEngineError.StreamError,
            };

            const null_terminated_string = self.allocator.dupeZ(u8, output_fbs.getWritten()[37..]) catch return FileEngineError.MemoryError;
            defer self.allocator.free(null_terminated_string);

            var data_toker = FileTokenizer.init(null_terminated_string);
            const uuid = UUID.parse(output_fbs.getWritten()[0..36]) catch return FileEngineError.InvalidUUID;

            founded = false;
            // Optimize this
            for (uuids) |elem| {
                if (elem.compare(uuid)) {
                    founded = true;
                    break;
                }
            }

            if (!founded) continue;

            // Maybe do a JSON writer wrapper
            out_writer.writeAll("{") catch return FileEngineError.WriteError;
            out_writer.writeAll("id:\"") catch return FileEngineError.WriteError;
            out_writer.print("{s}", .{output_fbs.getWritten()[0..36]}) catch return FileEngineError.WriteError;
            out_writer.writeAll("\", ") catch return FileEngineError.WriteError;
            for (try self.structName2structMembers(struct_name), try self.structName2DataType(struct_name)) |member_name, member_type| {
                token = data_toker.next();
                // FIXME: When relationship will be implemented, need to check if the len of NON link is 0
                if (!(additional_data.member_to_find.items.len == 0 or additional_data.contains(member_name))) continue;

                // write the member name and = sign
                out_writer.print("{s}: ", .{member_name}) catch return FileEngineError.WriteError;

                switch (member_type) {
                    .str => {
                        const str_slice = data_toker.getTokenSlice(token);
                        out_writer.print("\"{s}\"", .{str_slice[1 .. str_slice.len - 1]}) catch return FileEngineError.WriteError;
                    },
                    .date, .time, .datetime => {
                        const str_slice = data_toker.getTokenSlice(token);
                        out_writer.print("\"{s}\"", .{str_slice}) catch return FileEngineError.WriteError;
                    },
                    .str_array => {
                        out_writer.writeAll(data_toker.getTokenSlice(token)) catch return FileEngineError.WriteError;
                        token = data_toker.next();
                        while (token.tag != .r_bracket) : (token = data_toker.next()) {
                            out_writer.writeAll("\"") catch return FileEngineError.WriteError;
                            out_writer.writeAll(data_toker.getTokenSlice(token)[1..(token.loc.end - token.loc.start)]) catch return FileEngineError.WriteError;
                            out_writer.writeAll("\", ") catch return FileEngineError.WriteError;
                        }
                        out_writer.writeAll(data_toker.getTokenSlice(token)) catch return FileEngineError.WriteError;
                    },
                    .date_array, .time_array, .datetime_array => {
                        out_writer.writeAll(data_toker.getTokenSlice(token)) catch return FileEngineError.WriteError;
                        token = data_toker.next();
                        while (token.tag != .r_bracket) : (token = data_toker.next()) {
                            out_writer.writeAll("\"") catch return FileEngineError.WriteError;
                            out_writer.writeAll(data_toker.getTokenSlice(token)) catch return FileEngineError.WriteError;
                            out_writer.writeAll("\", ") catch return FileEngineError.WriteError;
                        }
                        out_writer.writeAll(data_toker.getTokenSlice(token)) catch return FileEngineError.WriteError;
                    },
                    .int_array, .float_array, .bool_array => {
                        out_writer.writeAll(data_toker.getTokenSlice(token)) catch return FileEngineError.WriteError;
                        token = data_toker.next();
                        while (token.tag != .r_bracket) : (token = data_toker.next()) {
                            out_writer.writeAll(data_toker.getTokenSlice(token)) catch return FileEngineError.WriteError;
                            out_writer.writeAll(", ") catch return FileEngineError.WriteError;
                        }
                        out_writer.writeAll(data_toker.getTokenSlice(token)) catch return FileEngineError.WriteError;
                    },

                    .link => out_writer.writeAll("false") catch return FileEngineError.WriteError, // TODO: Get and send data
                    .link_array => out_writer.writeAll("false") catch return FileEngineError.WriteError, // TODO: Get and send data

                    else => out_writer.writeAll(data_toker.getTokenSlice(token)) catch return FileEngineError.WriteError, //write the value as if
                }
                out_writer.writeAll(", ") catch return FileEngineError.WriteError;
            }
            out_writer.writeAll("}") catch return FileEngineError.WriteError;
            out_writer.writeAll(", ") catch return FileEngineError.WriteError;
        }
        out_writer.writeAll("]") catch return FileEngineError.WriteError;
    }

    /// Use a struct name to populate a list with all UUID of this struct
    /// TODO: Optimize this, I'm sure I can do better than that
    pub fn getAllUUIDList(self: *FileEngine, struct_name: []const u8, uuid_array: *std.ArrayList(UUID)) FileEngineError!void {
        const max_file_index = try self.maxFileIndex(struct_name);
        var current_index: usize = 0;

        var path_buff = std.fmt.allocPrint(
            self.allocator,
            "{s}/DATA/{s}/{d}.csv",
            .{ self.path_to_ZipponDB_dir, struct_name, current_index },
        ) catch return FileEngineError.MemoryError;
        defer self.allocator.free(path_buff);

        var file = std.fs.cwd().openFile(path_buff, .{}) catch return FileEngineError.CantOpenFile;
        defer file.close();

        var output: [BUFFER_SIZE]u8 = undefined; // Maybe need to increase that as it limit the size of a line in a file
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
                    path_buff = std.fmt.allocPrint(
                        self.allocator,
                        "{s}/DATA/{s}/{d}.csv",
                        .{ self.path_to_ZipponDB_dir, struct_name, current_index },
                    ) catch return FileEngineError.MemoryError;

                    file.close(); // Do I need to close ? I think so
                    file = std.fs.cwd().openFile(path_buff, .{}) catch return FileEngineError.CantOpenFile;

                    buffered = std.io.bufferedReader(file.reader());
                    reader = buffered.reader();
                    continue;
                }, // file read till the end
                else => return FileEngineError.StreamError,
            };

            const uuid = try UUID.parse(output_fbs.getWritten()[0..36]);
            uuid_array.append(uuid) catch return FileEngineError.MemoryError;
        }
    }

    /// Take a condition and an array of UUID and fill the array with all UUID that match the condition
    /// TODO: Change the UUID function to be a B+Tree
    /// TODO: Optimize the shit out of this, it it way too slow rn. Here some ideas
    /// - Make multiple condition per row
    /// - Array can take a very long time to parse, maybe put them in a seperate file. But string can be too...
    /// - Use the stream directly in the tokenizer
    /// - Use a fixed size and split into other file. Like one file for one member (Because very long, like an array of 1000 value) and another one for everything else
    ///     The threselhold can be like if the average len is > 400 character. So UUID would take less that 10% of the storage
    /// - Save data in a more compact way
    /// - Multithreading, each thread take a list of files and we mix them at the end
    pub fn getUUIDListUsingCondition(self: *FileEngine, condition: Condition, uuid_array: *std.ArrayList(UUID)) FileEngineError!void {
        const max_file_index = try self.maxFileIndex(condition.struct_name);
        var current_index: usize = 0;

        var path_buff = std.fmt.allocPrint(
            self.allocator,
            "{s}/DATA/{s}/{d}.csv",
            .{ self.path_to_ZipponDB_dir, condition.struct_name, current_index },
        ) catch return FileEngineError.MemoryError;
        defer self.allocator.free(path_buff);

        var file = std.fs.cwd().openFile(path_buff, .{}) catch return FileEngineError.CantOpenFile;
        defer file.close();

        var output: [BUFFER_SIZE]u8 = undefined;
        var output_fbs = std.io.fixedBufferStream(&output);
        const writer = output_fbs.writer();

        var buffered = std.io.bufferedReader(file.reader());
        var reader = buffered.reader();

        var compare_value: ComparisonValue = undefined;
        switch (condition.data_type) {
            .int => compare_value = ComparisonValue{ .int = s2t.parseInt(condition.value) },
            .str => compare_value = ComparisonValue{ .str = condition.value },
            .float => compare_value = ComparisonValue{ .float = s2t.parseFloat(condition.value) },
            .bool => compare_value = ComparisonValue{ .bool_ = s2t.parseBool(condition.value) },
            .link => compare_value = ComparisonValue{ .link = UUID.parse(condition.value) catch return FileEngineError.InvalidUUID },
            .date => compare_value = ComparisonValue{ .datetime = s2t.parseDate(condition.value) },
            .time => compare_value = ComparisonValue{ .datetime = s2t.parseTime(condition.value) },
            .datetime => compare_value = ComparisonValue{ .datetime = s2t.parseDatetime(condition.value) },
            .int_array => compare_value = ComparisonValue{ .int_array = s2t.parseArrayInt(self.allocator, condition.value) },
            .str_array => compare_value = ComparisonValue{ .str_array = s2t.parseArrayStr(self.allocator, condition.value) },
            .float_array => compare_value = ComparisonValue{ .float_array = s2t.parseArrayFloat(self.allocator, condition.value) },
            .bool_array => compare_value = ComparisonValue{ .bool_array = s2t.parseArrayBool(self.allocator, condition.value) },
            .link_array => compare_value = ComparisonValue{ .link_array = s2t.parseArrayUUID(self.allocator, condition.value) },
            .date_array => compare_value = ComparisonValue{ .datetime_array = s2t.parseArrayDate(self.allocator, condition.value) },
            .time_array => compare_value = ComparisonValue{ .datetime_array = s2t.parseArrayTime(self.allocator, condition.value) },
            .datetime_array => compare_value = ComparisonValue{ .datetime_array = s2t.parseArrayDatetime(self.allocator, condition.value) },
        }
        defer {
            switch (condition.data_type) {
                .int_array => compare_value.int_array.deinit(),
                .str_array => {
                    for (compare_value.str_array.items) |value| self.allocator.free(value); // TODO: Remove that, I should need to free them one by one as condition.value keep it in memory
                    compare_value.str_array.deinit();
                },
                .float_array => compare_value.float_array.deinit(),
                .bool_array => compare_value.bool_array.deinit(),
                .link_array => compare_value.link_array.deinit(),
                .datetime_array => compare_value.datetime_array.deinit(),
                else => {},
            }
        }

        var token: FileToken = undefined;
        var found = false;

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
                    path_buff = std.fmt.allocPrint(
                        self.allocator,
                        "{s}/DATA/{s}/{d}.csv",
                        .{ self.path_to_ZipponDB_dir, condition.struct_name, current_index },
                    ) catch return FileEngineError.MemoryError;

                    file.close(); // Do I need to close ? I think so
                    file = std.fs.cwd().openFile(path_buff, .{}) catch return FileEngineError.CantOpenFile;

                    buffered = std.io.bufferedReader(file.reader());
                    reader = buffered.reader();
                    continue;
                }, // file read till the end
                else => return FileEngineError.StreamError,
            };

            // Maybe use the stream directly to prevent duplicate the data
            // But I would need to change the Tokenizer a lot...
            const null_terminated_string = self.allocator.dupeZ(u8, output_fbs.getWritten()[37..]) catch return FileEngineError.MemoryError;
            defer self.allocator.free(null_terminated_string);

            var data_toker = FileTokenizer.init(null_terminated_string);
            const uuid = UUID.parse(output_fbs.getWritten()[0..36]) catch return FileEngineError.InvalidUUID;

            // Skip unwanted token
            for (try self.structName2structMembers(condition.struct_name)) |member_name| {
                if (std.mem.eql(u8, member_name, condition.member_name)) break;
                _ = data_toker.next();
            }
            token = data_toker.next();

            const row_value = data_toker.getTokenSlice(token);

            found = switch (condition.operation) {
                .equal => switch (condition.data_type) {
                    .int => compare_value.int == s2t.parseInt(row_value),
                    .float => compare_value.float == s2t.parseFloat(row_value),
                    .str => std.mem.eql(u8, compare_value.str, row_value),
                    .bool => compare_value.bool_ == s2t.parseBool(row_value),
                    .link => compare_value.link.compare(uuid),
                    .date => compare_value.datetime.compareDate(s2t.parseDate(row_value)),
                    .time => compare_value.datetime.compareTime(s2t.parseTime(row_value)),
                    .datetime => compare_value.datetime.compareDatetime(s2t.parseDatetime(row_value)),
                    else => unreachable,
                },

                .different => switch (condition.data_type) {
                    .int => compare_value.int != s2t.parseInt(row_value),
                    .float => compare_value.float != s2t.parseFloat(row_value),
                    .str => !std.mem.eql(u8, compare_value.str, row_value),
                    .bool => compare_value.bool_ != s2t.parseBool(row_value),
                    .link => !compare_value.link.compare(uuid),
                    .date => !compare_value.datetime.compareDate(s2t.parseDate(row_value)),
                    .time => !compare_value.datetime.compareTime(s2t.parseTime(row_value)),
                    .datetime => !compare_value.datetime.compareDatetime(s2t.parseDatetime(row_value)),
                    else => unreachable,
                },

                .superior_or_equal => switch (condition.data_type) {
                    .int => compare_value.int <= s2t.parseInt(data_toker.getTokenSlice(token)),
                    .float => compare_value.float <= s2t.parseFloat(data_toker.getTokenSlice(token)),
                    .date => compare_value.datetime.toUnix() <= s2t.parseDate(row_value).toUnix(),
                    .time => compare_value.datetime.toUnix() <= s2t.parseTime(row_value).toUnix(),
                    .datetime => compare_value.datetime.toUnix() <= s2t.parseDatetime(row_value).toUnix(),
                    else => unreachable,
                },

                .superior => switch (condition.data_type) {
                    .int => compare_value.int < s2t.parseInt(data_toker.getTokenSlice(token)),
                    .float => compare_value.float < s2t.parseFloat(data_toker.getTokenSlice(token)),
                    .date => compare_value.datetime.toUnix() < s2t.parseDate(row_value).toUnix(),
                    .time => compare_value.datetime.toUnix() < s2t.parseTime(row_value).toUnix(),
                    .datetime => compare_value.datetime.toUnix() < s2t.parseDatetime(row_value).toUnix(),
                    else => unreachable,
                },

                .inferior_or_equal => switch (condition.data_type) {
                    .int => compare_value.int >= s2t.parseInt(data_toker.getTokenSlice(token)),
                    .float => compare_value.float >= s2t.parseFloat(data_toker.getTokenSlice(token)),
                    .date => compare_value.datetime.toUnix() >= s2t.parseDate(row_value).toUnix(),
                    .time => compare_value.datetime.toUnix() >= s2t.parseTime(row_value).toUnix(),
                    .datetime => compare_value.datetime.toUnix() >= s2t.parseDatetime(row_value).toUnix(),
                    else => unreachable,
                },

                .inferior => switch (condition.data_type) {
                    .int => compare_value.int > s2t.parseInt(data_toker.getTokenSlice(token)),
                    .float => compare_value.float > s2t.parseFloat(data_toker.getTokenSlice(token)),
                    .date => compare_value.datetime.toUnix() > s2t.parseDate(row_value).toUnix(),
                    .time => compare_value.datetime.toUnix() > s2t.parseTime(row_value).toUnix(),
                    .datetime => compare_value.datetime.toUnix() > s2t.parseDatetime(row_value).toUnix(),
                    else => unreachable,
                },

                else => false,
            };

            // TODO: Do it for other array and implement in the query language
            switch (condition.operation) {
                .in => switch (condition.data_type) {
                    .link_array => {
                        for (compare_value.link_array.items) |elem| {
                            if (elem.compare(uuid)) uuid_array.append(uuid) catch return FileEngineError.MemoryError;
                        }
                    },
                    else => unreachable,
                },
                else => {},
            }

            if (found) uuid_array.append(uuid) catch return FileEngineError.MemoryError;
        }
    }

    // --------------------Change existing files--------------------

    // Do I need a map here ? Cant I use something else ?
    pub fn writeEntity(self: *FileEngine, struct_name: []const u8, data_map: std.StringHashMap([]const u8)) FileEngineError!UUID {
        const uuid = UUID.init();

        const potential_file_index = try self.getFirstUsableIndexFile(struct_name);
        var file: std.fs.File = undefined;
        defer file.close();

        var path: []const u8 = undefined;
        defer self.allocator.free(path);

        if (potential_file_index) |file_index| {
            path = std.fmt.allocPrint(
                self.allocator,
                "{s}/DATA/{s}/{d}.csv",
                .{ self.path_to_ZipponDB_dir, struct_name, file_index },
            ) catch return FileEngineError.MemoryError;
            file = std.fs.cwd().openFile(path, .{ .mode = .read_write }) catch return FileEngineError.CantOpenFile;
        } else {
            const max_index = try self.maxFileIndex(struct_name);

            path = std.fmt.allocPrint(
                self.allocator,
                "{s}/DATA/{s}/{d}.csv",
                .{ self.path_to_ZipponDB_dir, struct_name, max_index + 1 },
            ) catch return FileEngineError.MemoryError;
            file = std.fs.cwd().createFile(path, .{}) catch return FileEngineError.CantMakeFile;
        }

        file.seekFromEnd(0) catch return FileEngineError.WriteError; // Not really a write error tho
        const writer = file.writer();
        writer.print("{s}", .{uuid.format_uuid()}) catch return FileEngineError.WriteError;

        for (try self.structName2structMembers(struct_name)) |member_name| {
            writer.writeByte(CSV_DELIMITER) catch return FileEngineError.WriteError;
            writer.print("{s}", .{data_map.get(member_name).?}) catch return FileEngineError.WriteError; // Change that for csv
        }

        writer.print("\n", .{}) catch return FileEngineError.WriteError;

        return uuid;
    }

    /// Function to update the file with updated data. Take a list of uuid and a list of string map. The map is in the format key: member; value: new value.
    /// It create a new index.zippondata.new file in the same folder, stream the output of the old file to it until a uuid is found, then write the new row and continue until the end
    /// TODO: Optmize a lot, I did that quickly to work but it is far from optimized. Idea:
    ///     - Once all uuid found, stream until the end of the file without delimiter or uuid compare
    ///     - Change map to array
    pub fn updateEntities(self: *FileEngine, struct_name: []const u8, uuids: []UUID, new_data_map: std.StringHashMap([]const u8)) FileEngineError!void {
        const max_file_index = try self.maxFileIndex(struct_name);
        var current_file_index: usize = 0;

        var path_buff = std.fmt.allocPrint(
            self.allocator,
            "{s}/DATA/{s}/{d}.csv",
            .{ self.path_to_ZipponDB_dir, struct_name, current_file_index },
        ) catch return FileEngineError.MemoryError;
        defer self.allocator.free(path_buff);

        var path_buff2 = std.fmt.allocPrint(
            self.allocator,
            "{s}/DATA/{s}/{d}.csv",
            .{ self.path_to_ZipponDB_dir, struct_name, current_file_index },
        ) catch return FileEngineError.MemoryError;
        defer self.allocator.free(path_buff2);

        var old_file = std.fs.cwd().openFile(path_buff, .{}) catch return FileEngineError.CantOpenFile;

        self.allocator.free(path_buff);
        path_buff = std.fmt.allocPrint(
            self.allocator,
            "{s}/DATA/{s}/{d}.csv.new",
            .{ self.path_to_ZipponDB_dir, struct_name, current_file_index },
        ) catch return FileEngineError.MemoryError;

        var new_file = std.fs.cwd().createFile(path_buff, .{}) catch return FileEngineError.CantOpenFile;
        defer new_file.close();

        var output: [BUFFER_SIZE]u8 = undefined; // Maybe need to increase that as it limit the size of a line in a file
        var output_fbs = std.io.fixedBufferStream(&output);
        const writer = output_fbs.writer();

        var buffered = std.io.bufferedReader(old_file.reader());
        var reader = buffered.reader();
        var founded = false;
        const number_of_member_in_struct = try self.numberOfMemberInStruct(struct_name);

        while (true) {
            output_fbs.reset();
            reader.streamUntilDelimiter(writer, CSV_DELIMITER, null) catch |err| switch (err) {
                error.EndOfStream => {
                    // When end of file, check if all file was parse, if not update the reader to the next file
                    // TODO: Be able to give an array of file index from the B+Tree to only parse them
                    output_fbs.reset(); // clear buffer before exit

                    // Start by deleting and renaming the new file
                    self.allocator.free(path_buff);
                    path_buff = std.fmt.allocPrint(
                        self.allocator,
                        "{s}/DATA/{s}/{d}.csv",
                        .{ self.path_to_ZipponDB_dir, struct_name, current_file_index },
                    ) catch return FileEngineError.MemoryError;

                    self.allocator.free(path_buff2);
                    path_buff2 = std.fmt.allocPrint(
                        self.allocator,
                        "{s}/DATA/{s}/{d}.csv.new",
                        .{ self.path_to_ZipponDB_dir, struct_name, current_file_index },
                    ) catch return FileEngineError.MemoryError;

                    old_file.close();
                    std.fs.cwd().deleteFile(path_buff) catch return FileEngineError.DeleteFileError;
                    std.fs.cwd().rename(path_buff2, path_buff) catch return FileEngineError.RenameFileError;

                    if (current_file_index == max_file_index) break;

                    current_file_index += 1;

                    self.allocator.free(path_buff);
                    path_buff = std.fmt.allocPrint(
                        self.allocator,
                        "{s}/DATA/{s}/{d}.csv",
                        .{ self.path_to_ZipponDB_dir, struct_name, current_file_index },
                    ) catch return FileEngineError.MemoryError;

                    self.allocator.free(path_buff2);
                    path_buff2 = std.fmt.allocPrint(self.allocator, "{s}/DATA/{s}/{d}.csv.new", .{
                        self.path_to_ZipponDB_dir,
                        struct_name,
                        current_file_index,
                    }) catch return FileEngineError.MemoryError;

                    old_file = std.fs.cwd().openFile(path_buff, .{}) catch return FileEngineError.CantOpenFile;

                    new_file = std.fs.cwd().createFile(path_buff2, .{}) catch return FileEngineError.CantMakeFile;

                    buffered = std.io.bufferedReader(old_file.reader());
                    reader = buffered.reader();
                    continue;
                }, // file read till the end
                else => return FileEngineError.StreamError,
            };

            const new_writer = new_file.writer();

            new_writer.writeAll(output_fbs.getWritten()) catch return FileEngineError.WriteError;

            // THis is the uuid of the current row
            const uuid = UUID.parse(output_fbs.getWritten()[0..36]) catch return FileEngineError.InvalidUUID;
            founded = false;

            // Optimize this
            for (uuids) |elem| {
                if (elem.compare(uuid)) {
                    founded = true;
                    break;
                }
            }

            if (!founded) {
                // stream until the delimiter
                output_fbs.reset();
                new_writer.writeByte(CSV_DELIMITER) catch return FileEngineError.WriteError;
                reader.streamUntilDelimiter(writer, '\n', null) catch return FileEngineError.WriteError;
                new_writer.writeAll(output_fbs.getWritten()) catch return FileEngineError.WriteError;
                new_writer.writeAll("\n") catch return FileEngineError.WriteError;
            } else {
                for (try self.structName2structMembers(struct_name), try self.structName2DataType(struct_name), 0..) |member_name, member_type, i| {
                    // For all collum in the right order, check if the key is in the map, if so use it to write the new value, otherwise use the old file
                    output_fbs.reset();
                    switch (member_type) {
                        .str => {
                            reader.streamUntilDelimiter(writer, '\'', null) catch return FileEngineError.StreamError;
                            reader.streamUntilDelimiter(writer, '\'', null) catch return FileEngineError.StreamError;
                        },
                        .int_array, .float_array, .bool_array, .link_array, .date_array, .time_array, .datetime_array => {
                            reader.streamUntilDelimiter(writer, ']', null) catch return FileEngineError.StreamError;
                        },
                        .str_array => {
                            reader.streamUntilDelimiter(writer, ']', null) catch return FileEngineError.StreamError;
                        }, // FIXME: If the string itself contain ], this will be a problem
                        else => {
                            reader.streamUntilDelimiter(writer, CSV_DELIMITER, null) catch return FileEngineError.StreamError;
                        },
                    }

                    new_writer.writeByte(CSV_DELIMITER) catch return FileEngineError.WriteError;

                    if (new_data_map.contains(member_name)) {
                        // Write the new data
                        new_writer.print("{s}", .{new_data_map.get(member_name).?}) catch return FileEngineError.WriteError;
                    } else {
                        // Write the old data
                        switch (member_type) {
                            .str => new_writer.writeByte('\'') catch return FileEngineError.WriteError,
                            else => {},
                        }
                        new_writer.writeAll(output_fbs.getWritten()) catch return FileEngineError.WriteError;
                        switch (member_type) {
                            .str => {
                                new_writer.writeByte('\'') catch return FileEngineError.WriteError;
                            },
                            .int_array, .float_array, .bool_array, .link_array, .date_array, .str_array, .time_array, .datetime_array => {
                                new_writer.writeByte(']') catch return FileEngineError.WriteError;
                            },
                            else => {},
                        }
                    }

                    if (i == number_of_member_in_struct - 1) continue;
                    switch (member_type) {
                        .str, .int_array, .float_array, .bool_array, .link_array, .date_array, .str_array, .time_array, .datetime_array => {
                            reader.streamUntilDelimiter(writer, CSV_DELIMITER, null) catch return FileEngineError.StreamError;
                        },
                        else => {},
                    }
                }

                reader.streamUntilDelimiter(writer, '\n', null) catch return FileEngineError.StreamError;
                new_writer.writeAll("\n") catch return FileEngineError.WriteError;
            }
        }
    }

    /// Take a kist of UUID and a struct name and delete the row with same UUID
    /// TODO: Use B+Tree
    pub fn deleteEntities(self: *FileEngine, struct_name: []const u8, uuids: []UUID) FileEngineError!usize {
        const max_file_index = self.maxFileIndex(struct_name) catch @panic("Cant get max index file when updating");
        var current_file_index: usize = 0;

        var path_buff = std.fmt.allocPrint(
            self.allocator,
            "{s}/DATA/{s}/{d}.csv",
            .{ self.path_to_ZipponDB_dir, struct_name, current_file_index },
        ) catch return FileEngineError.MemoryError;
        defer self.allocator.free(path_buff);

        var path_buff2 = std.fmt.allocPrint(
            self.allocator,
            "{s}/DATA/{s}/{d}.csv",
            .{ self.path_to_ZipponDB_dir, struct_name, current_file_index },
        ) catch return FileEngineError.MemoryError;
        defer self.allocator.free(path_buff2);

        var old_file = std.fs.cwd().openFile(path_buff, .{}) catch return FileEngineError.CantOpenFile;

        self.allocator.free(path_buff);
        path_buff = std.fmt.allocPrint(
            self.allocator,
            "{s}/DATA/{s}/{d}.csv.new",
            .{ self.path_to_ZipponDB_dir, struct_name, current_file_index },
        ) catch return FileEngineError.MemoryError;

        var new_file = std.fs.cwd().createFile(path_buff, .{}) catch return FileEngineError.CantOpenFile;
        defer new_file.close();

        var output: [BUFFER_SIZE]u8 = undefined; // Maybe need to increase that as it limit the size of a line in a file
        var output_fbs = std.io.fixedBufferStream(&output);
        const writer = output_fbs.writer();

        var buffered = std.io.bufferedReader(old_file.reader());
        var reader = buffered.reader();
        var founded = false;
        var deleted_count: usize = 0;

        while (true) {
            output_fbs.reset();
            reader.streamUntilDelimiter(writer, CSV_DELIMITER, null) catch |err| switch (err) {
                error.EndOfStream => {
                    // When end of file, check if all file was parse, if not update the reader to the next file
                    // TODO: Be able to give an array of file index from the B+Tree to only parse them
                    output_fbs.reset(); // clear buffer before exit

                    // Start by deleting and renaming the new file
                    self.allocator.free(path_buff);
                    path_buff = std.fmt.allocPrint(
                        self.allocator,
                        "{s}/DATA/{s}/{d}.csv",
                        .{ self.path_to_ZipponDB_dir, struct_name, current_file_index },
                    ) catch return FileEngineError.MemoryError;

                    self.allocator.free(path_buff2);
                    path_buff2 = std.fmt.allocPrint(
                        self.allocator,
                        "{s}/DATA/{s}/{d}.csv.new",
                        .{ self.path_to_ZipponDB_dir, struct_name, current_file_index },
                    ) catch return FileEngineError.MemoryError;

                    old_file.close();
                    std.fs.cwd().deleteFile(path_buff) catch return FileEngineError.DeleteFileError;
                    std.fs.cwd().rename(path_buff2, path_buff) catch return FileEngineError.RenameFileError;

                    if (current_file_index == max_file_index) break;

                    current_file_index += 1;

                    self.allocator.free(path_buff);
                    path_buff = std.fmt.allocPrint(
                        self.allocator,
                        "{s}/DATA/{s}/{d}.csv",
                        .{ self.path_to_ZipponDB_dir, struct_name, current_file_index },
                    ) catch return FileEngineError.MemoryError;

                    self.allocator.free(path_buff2);
                    path_buff2 = std.fmt.allocPrint(
                        self.allocator,
                        "{s}/DATA/{s}/{d}.csv.new",
                        .{ self.path_to_ZipponDB_dir, struct_name, current_file_index },
                    ) catch return FileEngineError.MemoryError;

                    old_file = std.fs.cwd().openFile(path_buff, .{}) catch return FileEngineError.CantOpenFile;

                    new_file = std.fs.cwd().createFile(path_buff2, .{}) catch return FileEngineError.CantOpenFile;

                    buffered = std.io.bufferedReader(old_file.reader());
                    reader = buffered.reader();
                    continue;
                }, // file read till the end
                else => {
                    log.err("Error while reading file: {any}", .{err});
                    break;
                },
            };

            const new_writer = new_file.writer();

            // THis is the uuid of the current row
            const uuid = UUID.parse(output_fbs.getWritten()[0..36]) catch return FileEngineError.InvalidUUID;
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
                new_writer.writeAll(output_fbs.getWritten()) catch return FileEngineError.WriteError;

                output_fbs.reset();
                new_writer.writeByte(CSV_DELIMITER) catch return FileEngineError.WriteError;
                reader.streamUntilDelimiter(writer, '\n', null) catch return FileEngineError.WriteError;
                new_writer.writeAll(output_fbs.getWritten()) catch return FileEngineError.WriteError;
                new_writer.writeByte('\n') catch return FileEngineError.WriteError;
            } else {
                reader.streamUntilDelimiter(writer, '\n', null) catch return FileEngineError.WriteError;
            }
        }

        return deleted_count;
    }

    // --------------------Schema utils--------------------

    /// Get the index of the first file that is bellow the size limit. If not found, return null
    fn getFirstUsableIndexFile(self: FileEngine, struct_name: []const u8) FileEngineError!?usize {
        const path = std.fmt.allocPrint(
            self.allocator,
            "{s}/DATA/{s}",
            .{ self.path_to_ZipponDB_dir, struct_name },
        ) catch return FileEngineError.MemoryError;
        defer self.allocator.free(path);

        var member_dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return FileEngineError.CantOpenDir;
        defer member_dir.close();

        var iter = member_dir.iterate();
        while (iter.next() catch return FileEngineError.DirIterError) |entry| {
            const file_stat = member_dir.statFile(entry.name) catch return FileEngineError.FileStatError;
            if (file_stat.size < MAX_FILE_SIZE) {
                return std.fmt.parseInt(usize, entry.name[0..(entry.name.len - 4)], 10) catch return FileEngineError.InvalidFileIndex; // TODO: Change the slice when start using CSV
            }
        }
        return null;
    }

    /// Iterate over all file of a struct and return the index of the last file.
    /// E.g. a struct with 0.csv and 1.csv it return 1.
    fn maxFileIndex(self: FileEngine, struct_name: []const u8) FileEngineError!usize {
        const path = std.fmt.allocPrint(
            self.allocator,
            "{s}/DATA/{s}",
            .{ self.path_to_ZipponDB_dir, struct_name },
        ) catch return FileEngineError.MemoryError;
        defer self.allocator.free(path);

        const member_dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return FileEngineError.CantOpenDir;
        var count: usize = 0;

        var iter = member_dir.iterate();
        while (iter.next() catch return FileEngineError.DirIterError) |entry| {
            if (entry.kind != .file) continue;
            count += 1;
        }
        return count - 1;
    }

    pub fn isSchemaFileInDir(self: *FileEngine) bool {
        const path = std.fmt.allocPrint(
            self.allocator,
            "{s}/schema.zipponschema",
            .{self.path_to_ZipponDB_dir},
        ) catch return false;
        defer self.allocator.free(path);

        _ = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return false;
        return true;
    }

    pub fn writeSchemaFile(self: *FileEngine) FileEngineError!void {
        var zippon_dir = std.fs.cwd().openDir(self.path_to_ZipponDB_dir, .{}) catch return FileEngineError.MemoryError;
        defer zippon_dir.close();

        zippon_dir.deleteFile("schema.zipponschema") catch |err| switch (err) {
            error.FileNotFound => {},
            else => return FileEngineError.DeleteFileError,
        };

        var file = zippon_dir.createFile("schema.zipponschema", .{}) catch return FileEngineError.CantMakeFile;
        defer file.close();
        file.writeAll(self.null_terminated_schema_buff) catch return FileEngineError.WriteError;
    }

    /// Get the type of the member
    pub fn memberName2DataType(self: *FileEngine, struct_name: []const u8, member_name: []const u8) FileEngineError!DataType {
        var i: u16 = 0;

        for (try self.structName2structMembers(struct_name)) |mn| {
            const dtypes = try self.structName2DataType(struct_name);
            if (std.mem.eql(u8, mn, member_name)) return dtypes[i];
            i += 1;
        }

        return FileEngineError.MemberNotFound;
    }

    /// Get the list of all member name for a struct name
    pub fn structName2structMembers(self: *FileEngine, struct_name: []const u8) FileEngineError![][]const u8 {
        var i: u16 = 0;

        while (i < self.struct_array.items.len) : (i += 1) if (std.mem.eql(u8, self.struct_array.items[i].name, struct_name)) break;

        if (i == self.struct_array.items.len) {
            return FileEngineError.StructNotFound;
        }

        return self.struct_array.items[i].members.items;
    }

    pub fn structName2DataType(self: *FileEngine, struct_name: []const u8) FileEngineError![]const DataType {
        var i: u16 = 0;

        while (i < self.struct_array.items.len) : (i += 1) {
            if (std.mem.eql(u8, self.struct_array.items[i].name, struct_name)) break;
        }

        if (i == self.struct_array.items.len and !std.mem.eql(u8, self.struct_array.items[i].name, struct_name)) {
            return FileEngineError.StructNotFound;
        }

        return self.struct_array.items[i].types.items;
    }

    /// Return the number of member of a struct
    fn numberOfMemberInStruct(self: *FileEngine, struct_name: []const u8) FileEngineError!usize {
        var i: usize = 0;

        for (try self.structName2structMembers(struct_name)) |_| {
            i += 1;
        }

        return i;
    }

    /// Chech if the name of a struct is in the current schema
    pub fn isStructNameExists(self: *FileEngine, struct_name: []const u8) bool {
        var i: u16 = 0;
        while (i < self.struct_array.items.len) : (i += 1) if (std.mem.eql(u8, self.struct_array.items[i].name, struct_name)) return true;
        return false;
    }

    /// Check if a struct have the member name
    pub fn isMemberNameInStruct(self: *FileEngine, struct_name: []const u8, member_name: []const u8) FileEngineError!bool {
        for (try self.structName2structMembers(struct_name)) |mn| { // I do not return an error here because I should already check before is the struct exist
            if (std.mem.eql(u8, mn, member_name)) return true;
        }
        return false;
    }

    // Return true if the map have all the member name as key and not more
    pub fn checkIfAllMemberInMap(self: *FileEngine, struct_name: []const u8, map: *std.StringHashMap([]const u8), error_message_buffer: *std.ArrayList(u8)) FileEngineError!bool {
        const all_struct_member = try self.structName2structMembers(struct_name);
        var count: u16 = 0;

        const writer = error_message_buffer.writer();

        for (all_struct_member) |mn| {
            if (map.contains(mn)) count += 1 else writer.print(" {s},", .{mn}) catch return FileEngineError.WriteError; // TODO: Handle missing print better
        }

        return ((count == all_struct_member.len) and (count == map.count()));
    }
};
