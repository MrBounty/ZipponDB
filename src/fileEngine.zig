const std = @import("std");
const utils = @import("stuffs/utils.zig");
const dtype = @import("dtype");
const s2t = dtype.s2t;
const zid = @import("ZipponData");
const Allocator = std.mem.Allocator;

const UUID = dtype.UUID;
const DateTime = dtype.DateTime;
const DataType = dtype.DataType;

const FileTokenizer = @import("tokenizers/file.zig").Tokenizer;
const FileToken = @import("tokenizers/file.zig").Token;
const SchemaTokenizer = @import("tokenizers/schema.zig").Tokenizer;
const SchemaToken = @import("tokenizers/schema.zig").Token;
const AdditionalData = @import("stuffs/additionalData.zig").AdditionalData;
const Loc = @import("tokenizers/shared/loc.zig").Loc;

const Condition = @import("stuffs/filter.zig").Condition;

// TODO: Move that to another struct, not in the file engine
const SchemaStruct = @import("schemaParser.zig").Parser.SchemaStruct;
const SchemaParser = @import("schemaParser.zig").Parser;

const FileEngineError = @import("stuffs/errors.zig").FileEngineError;

const config = @import("config.zig");
const BUFFER_SIZE = config.BUFFER_SIZE;
const MAX_FILE_SIZE = config.MAX_FILE_SIZE;
const CSV_DELIMITER = config.CSV_DELIMITER;
const RESET_LOG_AT_RESTART = config.RESET_LOG_AT_RESTART;

const log = std.log.scoped(.fileEngine);

/// Manage everything that is relate to read or write in files
/// Or even get stats, whatever. If it touch files, it's here
pub const FileEngine = struct {
    allocator: Allocator,
    path_to_ZipponDB_dir: []const u8,
    null_terminated_schema_buff: [:0]u8,
    struct_array: []SchemaStruct,

    pub fn init(allocator: Allocator, path: []const u8) FileEngineError!FileEngine {
        const path_to_ZipponDB_dir = path;

        var schema_buf = allocator.alloc(u8, BUFFER_SIZE) catch return FileEngineError.MemoryError;
        defer allocator.free(schema_buf);

        const len: usize = FileEngine.readSchemaFile(allocator, path_to_ZipponDB_dir, schema_buf) catch 0;
        const null_terminated_schema_buff = allocator.dupeZ(u8, schema_buf[0..len]) catch return FileEngineError.MemoryError;

        var toker = SchemaTokenizer.init(null_terminated_schema_buff);
        var parser = SchemaParser.init(&toker, allocator);

        var struct_array = std.ArrayList(SchemaStruct).init(allocator);
        parser.parse(&struct_array) catch {};

        return FileEngine{
            .allocator = allocator,
            .path_to_ZipponDB_dir = path_to_ZipponDB_dir,
            .null_terminated_schema_buff = null_terminated_schema_buff,
            .struct_array = struct_array.toOwnedSlice() catch return FileEngineError.MemoryError,
        };
    }

    pub fn deinit(self: *FileEngine) void {
        for (self.struct_array) |*elem| elem.deinit();
        self.allocator.free(self.struct_array);
        self.allocator.free(self.null_terminated_schema_buff);
        self.allocator.free(self.path_to_ZipponDB_dir);
    }

    pub fn usable(self: FileEngine) bool {
        return !std.mem.eql(u8, "", self.path_to_ZipponDB_dir);
    }

    // --------------------Other--------------------

    pub fn readSchemaFile(allocator: Allocator, sub_path: []const u8, buffer: []u8) FileEngineError!usize {
        const path = std.fmt.allocPrint(allocator, "{s}/schema", .{sub_path}) catch return FileEngineError.MemoryError;
        defer allocator.free(path);

        const file = std.fs.cwd().openFile(path, .{}) catch return FileEngineError.CantOpenFile;
        defer file.close();

        const len = file.readAll(buffer) catch return FileEngineError.ReadError;
        return len;
    }

    // FIXME: This got an error, idk why
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
            error.PathAlreadyExists => {},
            else => return FileEngineError.CantMakeDir,
        };

        self.allocator.free(path_buff);
        path_buff = std.fmt.allocPrint(self.allocator, "{s}/LOG/log", .{self.path_to_ZipponDB_dir}) catch return FileEngineError.MemoryError;

        if (RESET_LOG_AT_RESTART) {
            _ = cwd.createFile(path_buff, .{}) catch return FileEngineError.CantMakeFile;
        } else {
            const log_dir = cwd.openDir(path_buff[0..(path_buff.len - 4)], .{ .iterate = true }) catch return FileEngineError.CantOpenDir;
            var iter = log_dir.iterate();

            var founded = false;
            while (iter.next() catch return FileEngineError.DirIterError) |entry| {
                if (std.mem.eql(u8, entry.name, "log")) founded = true;
            }
            if (!founded) _ = cwd.createFile(path_buff, .{}) catch return FileEngineError.CantMakeFile;
        }
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
        for (self.struct_array) |*elem| elem.deinit();
        self.allocator(self.struct_array);

        var struct_array = std.ArrayList(SchemaStruct).init(self.allocator);
        parser.parse(&struct_array) catch return error.SchemaNotConform;
        self.struct_array = struct_array.toOwnedSlice();

        const path = std.fmt.allocPrint(self.allocator, "{s}/DATA", .{self.path_to_ZipponDB_dir}) catch return FileEngineError.MemoryError;
        defer self.allocator.free(path);

        var data_dir = std.fs.cwd().openDir(path, .{}) catch return FileEngineError.CantOpenDir;
        defer data_dir.close();

        for (self.struct_array) |schema_struct| {
            data_dir.makeDir(schema_struct.name) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return FileEngineError.CantMakeDir,
            };
            const struct_dir = data_dir.openDir(schema_struct.name, .{}) catch return FileEngineError.CantOpenDir;

            zid.createFile("0.zid", struct_dir) catch return FileEngineError.CantMakeFile;
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
    /// TODO: Use the new filter and DataIterator
    pub fn getUUIDListUsingCondition(_: *FileEngine, _: Condition, _: *std.ArrayList(UUID)) FileEngineError!void {
        return;
    }

    // --------------------Change existing files--------------------

    // TODO: Make it in batch too
    pub fn writeEntity(self: *FileEngine, struct_name: []const u8, map: std.StringHashMap([]const u8)) FileEngineError!UUID {
        const uuid = UUID.init();

        const file_index = try self.getFirstUsableIndexFile(struct_name);

        const path = std.fmt.allocPrint(
            self.allocator,
            "{s}/DATA/{s}/{d}.zid",
            .{ self.path_to_ZipponDB_dir, struct_name, file_index },
        ) catch return FileEngineError.MemoryError;
        defer self.allocator.free(path);

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const data = try self.orderedNewData(arena.allocator(), struct_name, map);

        var writer = zid.DataWriter.init(path, null) catch return FileEngineError.ZipponDataError;
        writer.write(data) catch return FileEngineError.ZipponDataError;
        writer.flush() catch return FileEngineError.ZipponDataError;

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

    // --------------------ZipponData utils--------------------

    // Function that take a map from the parseNewData and return an ordered array of Data
    pub fn orderedNewData(self: *FileEngine, allocator: Allocator, struct_name: []const u8, map: std.StringHashMap([]const u8)) FileEngineError![]const zid.Data {
        const members = try self.structName2structMembers(struct_name);
        const types = try self.structName2DataType(struct_name);

        var datas = allocator.alloc(zid.Data, members.len) catch return FileEngineError.MemoryError;

        for (members, types, 0..) |member, dt, i| {
            switch (dt) {
                .int => datas[i] = zid.Data.initInt(s2t.parseInt(map.get(member).?)),
                .float => datas[i] = zid.Data.initFloat(s2t.parseFloat(map.get(member).?)),
                .bool => datas[i] = zid.Data.initBool(s2t.parseBool(map.get(member).?)),
                .date => datas[i] = zid.Data.initUnix(s2t.parseDate(map.get(member).?).toUnix()),
                .time => datas[i] = zid.Data.initUnix(s2t.parseTime(map.get(member).?).toUnix()),
                .datetime => datas[i] = zid.Data.initUnix(s2t.parseDatetime(map.get(member).?).toUnix()),
                .str => datas[i] = zid.Data.initStr(map.get(member).?),
                .link => {
                    const uuid = UUID.parse(map.get(member).?) catch return FileEngineError.InvalidUUID;
                    datas[i] = zid.Data{ .UUID = uuid.bytes };
                },
                .int_array => {
                    var array = s2t.parseArrayInt(allocator, map.get(member).?);
                    defer array.deinit();

                    datas[i] = zid.Data.initIntArray(zid.allocEncodArray.Int(allocator, array.items) catch return FileEngineError.AllocEncodError);
                },
                .float_array => {
                    var array = s2t.parseArrayFloat(allocator, map.get(member).?);
                    defer array.deinit();

                    datas[i] = zid.Data.initFloatArray(zid.allocEncodArray.Float(allocator, array.items) catch return FileEngineError.AllocEncodError);
                },
                .str_array => {
                    var array = s2t.parseArrayStr(allocator, map.get(member).?);
                    defer array.deinit();

                    datas[i] = zid.Data.initStrArray(zid.allocEncodArray.Str(allocator, array.items) catch return FileEngineError.AllocEncodError);
                },
                .bool_array => {
                    var array = s2t.parseArrayBool(allocator, map.get(member).?);
                    defer array.deinit();

                    datas[i] = zid.Data.initFloatArray(zid.allocEncodArray.Bool(allocator, array.items) catch return FileEngineError.AllocEncodError);
                },
                .link_array => {
                    const array = s2t.parseArrayUUIDBytes(allocator, map.get(member).?) catch return FileEngineError.MemoryError;
                    defer self.allocator.free(array);

                    datas[i] = zid.Data.initUUIDArray(zid.allocEncodArray.UUID(allocator, array) catch return FileEngineError.AllocEncodError);
                },
                .date_array => {
                    var array = s2t.parseArrayDateUnix(allocator, map.get(member).?);
                    defer array.deinit();

                    datas[i] = zid.Data.initUnixArray(zid.allocEncodArray.Unix(allocator, array.items) catch return FileEngineError.AllocEncodError);
                },
                .time_array => {
                    var array = s2t.parseArrayTimeUnix(allocator, map.get(member).?);
                    defer array.deinit();

                    datas[i] = zid.Data.initUnixArray(zid.allocEncodArray.Unix(allocator, array.items) catch return FileEngineError.AllocEncodError);
                },
                .datetime_array => {
                    var array = s2t.parseArrayDatetimeUnix(allocator, map.get(member).?);
                    defer array.deinit();

                    datas[i] = zid.Data.initUnixArray(zid.allocEncodArray.Unix(allocator, array.items) catch return FileEngineError.AllocEncodError);
                },
            }
        }

        return datas;
    }

    // --------------------Schema utils--------------------

    /// Get the index of the first file that is bellow the size limit. If not found, create a new file
    fn getFirstUsableIndexFile(self: FileEngine, struct_name: []const u8) FileEngineError!usize {
        log.debug("Getting first usable index file for {s} at {s}", .{ struct_name, self.path_to_ZipponDB_dir });

        var path = std.fmt.allocPrint(
            self.allocator,
            "{s}/DATA/{s}",
            .{ self.path_to_ZipponDB_dir, struct_name },
        ) catch return FileEngineError.MemoryError;
        defer self.allocator.free(path);

        var member_dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return FileEngineError.CantOpenDir;
        defer member_dir.close();

        var i: usize = 0;
        var iter = member_dir.iterate();
        while (iter.next() catch return FileEngineError.DirIterError) |entry| {
            i += 1;
            const file_stat = member_dir.statFile(entry.name) catch return FileEngineError.FileStatError;
            if (file_stat.size < MAX_FILE_SIZE) {
                // Cant I just return i ? It is supossed that files are ordered. I think I already check and it is not
                return std.fmt.parseInt(usize, entry.name[0..(entry.name.len - 4)], 10) catch return FileEngineError.InvalidFileIndex; // INFO: Hardcoded len of file extension
            }
        }

        i += 1;
        path = std.fmt.allocPrint(
            self.allocator,
            "{s}/DATA/{s}/{d}.zid",
            .{ self.path_to_ZipponDB_dir, struct_name, i },
        ) catch return FileEngineError.MemoryError;

        zid.createFile(path, null) catch return FileEngineError.ZipponDataError;

        return i;
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
            "{s}/schema",
            .{self.path_to_ZipponDB_dir},
        ) catch return false;
        defer self.allocator.free(path);

        _ = std.fs.cwd().openFile(path, .{}) catch return false;
        return true;
    }

    pub fn writeSchemaFile(self: *FileEngine) FileEngineError!void {
        var zippon_dir = std.fs.cwd().openDir(self.path_to_ZipponDB_dir, .{}) catch return FileEngineError.MemoryError;
        defer zippon_dir.close();

        zippon_dir.deleteFile("schema") catch |err| switch (err) {
            error.FileNotFound => {},
            else => return FileEngineError.DeleteFileError,
        };

        var file = zippon_dir.createFile("schema", .{}) catch return FileEngineError.CantMakeFile;
        defer file.close();
        file.writeAll(self.null_terminated_schema_buff) catch return FileEngineError.WriteError;
    }

    /// Get the type of the member
    pub fn memberName2DataType(self: *FileEngine, struct_name: []const u8, member_name: []const u8) FileEngineError!DataType {
        var i: usize = 0;

        for (try self.structName2structMembers(struct_name)) |mn| {
            const dtypes = try self.structName2DataType(struct_name);
            if (std.mem.eql(u8, mn, member_name)) return dtypes[i];
            i += 1;
        }

        return FileEngineError.MemberNotFound;
    }

    pub fn memberName2DataIndex(self: *FileEngine, struct_name: []const u8, member_name: []const u8) FileEngineError!usize {
        var i: usize = 0;

        for (try self.structName2structMembers(struct_name)) |mn| {
            if (std.mem.eql(u8, mn, member_name)) return i;
            i += 1;
        }

        return FileEngineError.MemberNotFound;
    }

    /// Get the list of all member name for a struct name
    pub fn structName2structMembers(self: *FileEngine, struct_name: []const u8) FileEngineError![][]const u8 {
        var i: usize = 0;

        while (i < self.struct_array.len) : (i += 1) if (std.mem.eql(u8, self.struct_array[i].name, struct_name)) break;

        if (i == self.struct_array.len) {
            return FileEngineError.StructNotFound;
        }

        return self.struct_array[i].members.items;
    }

    pub fn structName2DataType(self: *FileEngine, struct_name: []const u8) FileEngineError![]const DataType {
        var i: u16 = 0;

        while (i < self.struct_array.len) : (i += 1) {
            if (std.mem.eql(u8, self.struct_array[i].name, struct_name)) break;
        }

        if (i == self.struct_array.len and !std.mem.eql(u8, self.struct_array[i].name, struct_name)) {
            return FileEngineError.StructNotFound;
        }

        return self.struct_array[i].types.items;
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
        while (i < self.struct_array.len) : (i += 1) if (std.mem.eql(u8, self.struct_array[i].name, struct_name)) return true;
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
