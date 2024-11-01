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
const Filter = @import("stuffs/filter.zig").Filter;
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

        var schema_buf = allocator.alloc(u8, BUFFER_SIZE) catch return FileEngineError.MemoryError; // TODO: Use a list
        defer allocator.free(schema_buf);

        const len: usize = FileEngine.readSchemaFile(allocator, path_to_ZipponDB_dir, schema_buf) catch 0;
        const null_terminated_schema_buff = allocator.dupeZ(u8, schema_buf[0..len]) catch return FileEngineError.MemoryError;
        errdefer allocator.free(null_terminated_schema_buff);

        var toker = SchemaTokenizer.init(null_terminated_schema_buff);
        var parser = SchemaParser.init(&toker, allocator);

        var struct_array = std.ArrayList(SchemaStruct).init(allocator);
        parser.parse(&struct_array) catch return FileEngineError.SchemaNotConform;

        var file_engine = FileEngine{
            .allocator = allocator,
            .path_to_ZipponDB_dir = path_to_ZipponDB_dir,
            .null_terminated_schema_buff = null_terminated_schema_buff,
            .struct_array = struct_array.toOwnedSlice() catch return FileEngineError.MemoryError,
        };

        try file_engine.populateAllUUIDToFileIndexMap();

        return file_engine;
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
        self.allocator.free(self.struct_array);

        var struct_array = std.ArrayList(SchemaStruct).init(self.allocator);
        parser.parse(&struct_array) catch return error.SchemaNotConform;
        self.struct_array = struct_array.toOwnedSlice() catch return FileEngineError.MemoryError;

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

    // For all struct in shema, add the UUID/index_file into the map
    pub fn populateAllUUIDToFileIndexMap(self: *FileEngine) FileEngineError!void {
        for (self.struct_array) |*sstruct| { // Stand for schema struct
            const max_file_index = try self.maxFileIndex(sstruct.name);

            var path_buff = std.fmt.allocPrint(
                self.allocator,
                "{s}/DATA/{s}",
                .{ self.path_to_ZipponDB_dir, sstruct.name },
            ) catch return FileEngineError.MemoryError;
            defer self.allocator.free(path_buff);

            const dir = std.fs.cwd().openDir(path_buff, .{}) catch return FileEngineError.CantOpenDir;

            for (0..(max_file_index + 1)) |i| {
                self.allocator.free(path_buff);
                path_buff = std.fmt.allocPrint(self.allocator, "{d}.zid", .{i}) catch return FileEngineError.MemoryError;

                var iter = zid.DataIterator.init(self.allocator, path_buff, dir, sstruct.zid_schema) catch return FileEngineError.ZipponDataError;
                defer iter.deinit();
                while (iter.next() catch return FileEngineError.ZipponDataError) |row| {
                    sstruct.uuid_file_index.put(row[0].UUID, i) catch return FileEngineError.MemoryError;
                }
            }
        }
    }

    /// Use a struct name to populate a list with all UUID of this struct
    pub fn getAllUUIDList(self: *FileEngine, struct_name: []const u8, uuid_list: *std.ArrayList(UUID)) FileEngineError!void {
        var sstruct = try self.structName2SchemaStruct(struct_name);

        var iter = sstruct.uuid_file_index.keyIterator();
        while (iter.next()) |key| {
            uuid_list.append(UUID{ .bytes = key.* }) catch return FileEngineError.MemoryError;
        }
    }

    /// Take a condition and an array of UUID and fill the array with all UUID that match the condition
    pub fn getUUIDListUsingFilter(self: *FileEngine, struct_name: []const u8, filter: Filter, uuid_list: *std.ArrayList(UUID)) FileEngineError!void {
        const sstruct = try self.structName2SchemaStruct(struct_name);
        const max_file_index = try self.maxFileIndex(sstruct.name);

        var path_buff = std.fmt.allocPrint(
            self.allocator,
            "{s}/DATA/{s}",
            .{ self.path_to_ZipponDB_dir, sstruct.name },
        ) catch return FileEngineError.MemoryError;
        defer self.allocator.free(path_buff);

        const dir = std.fs.cwd().openDir(path_buff, .{}) catch return FileEngineError.CantOpenDir;

        for (0..(max_file_index + 1)) |i| {
            self.allocator.free(path_buff);
            path_buff = std.fmt.allocPrint(self.allocator, "{d}.zid", .{i}) catch return FileEngineError.MemoryError;

            var iter = zid.DataIterator.init(self.allocator, path_buff, dir, sstruct.zid_schema) catch return FileEngineError.ZipponDataError;
            defer iter.deinit();

            while (iter.next() catch return FileEngineError.ZipponDataError) |row| {
                if (!filter.evaluate(row)) uuid_list.append(UUID{ .bytes = row[0] });
            }
        }
    }

    /// Take a filter, parse all file and if one struct if validate by the filter, write it in a JSON format to the writer
    /// filter can be null. This will return all of them
    pub fn parseEntities(
        self: *FileEngine,
        struct_name: []const u8,
        filter: ?Filter,
        buffer: *std.ArrayList(u8),
        additional_data: *AdditionalData,
    ) FileEngineError!void {
        const sstruct = try self.structName2SchemaStruct(struct_name);
        const max_file_index = try self.maxFileIndex(sstruct.name);
        var total_currently_found: usize = 0;

        var path_buff = std.fmt.allocPrint(
            self.allocator,
            "{s}/DATA/{s}",
            .{ self.path_to_ZipponDB_dir, sstruct.name },
        ) catch return FileEngineError.MemoryError;
        defer self.allocator.free(path_buff);
        const dir = std.fs.cwd().openDir(path_buff, .{}) catch return FileEngineError.CantOpenDir;

        // If there is no member to find, that mean we need to return all members, so let's populate additional data with all of them
        if (additional_data.member_to_find.items.len == 0) {
            additional_data.populateWithEverything(self.allocator, sstruct.members) catch return FileEngineError.MemoryError;
        }

        var writer = buffer.writer();
        writer.writeAll("[") catch return FileEngineError.WriteError;
        for (0..(max_file_index + 1)) |file_index| { // TODO: Multi thread that
            self.allocator.free(path_buff);
            path_buff = std.fmt.allocPrint(self.allocator, "{d}.zid", .{file_index}) catch return FileEngineError.MemoryError;

            var iter = zid.DataIterator.init(self.allocator, path_buff, dir, sstruct.zid_schema) catch return FileEngineError.ZipponDataError;
            defer iter.deinit();

            blk: while (iter.next() catch return FileEngineError.ZipponDataError) |row| {
                if (filter != null) if (!filter.?.evaluate(row)) continue;

                writer.writeByte('{') catch return FileEngineError.WriteError;
                for (additional_data.member_to_find.items) |member| {
                    // write the member name and = sign
                    writer.print("{s}: ", .{member.name}) catch return FileEngineError.WriteError;

                    switch (row[member.index]) {
                        .Int => |v| writer.print("{d}", .{v}) catch return FileEngineError.WriteError,
                        .Float => |v| writer.print("{d}", .{v}) catch return FileEngineError.WriteError,
                        .Str => |v| writer.print("\"{s}\"", .{v}) catch return FileEngineError.WriteError,
                        .UUID => |v| writer.print("\"{s}\"", .{UUID.format_bytes(v)}) catch return FileEngineError.WriteError,
                        .Bool => |v| writer.print("{any}", .{v}) catch return FileEngineError.WriteError,
                        .Unix => |v| {
                            const datetime = DateTime.initUnix(v);
                            writer.writeByte('"') catch return FileEngineError.WriteError;
                            switch (try self.memberName2DataType(struct_name, member.name)) {
                                .date => datetime.format("YYYY/MM/DD", writer) catch return FileEngineError.WriteError,
                                .time => datetime.format("HH:mm:ss.SSSS", writer) catch return FileEngineError.WriteError,
                                .datetime => datetime.format("YYYY/MM/DD-HH:mm:ss.SSSS", writer) catch return FileEngineError.WriteError,
                                else => unreachable,
                            }
                            writer.writeByte('"') catch return FileEngineError.WriteError;
                        },
                        .IntArray, .FloatArray, .StrArray, .UUIDArray, .BoolArray => try writeArray(&row[member.index], writer, null),
                        .UnixArray => try writeArray(&row[member.index], writer, try self.memberName2DataType(struct_name, member.name)),
                    }
                    writer.writeAll(", ") catch return FileEngineError.WriteError;
                }
                writer.writeAll("}, ") catch return FileEngineError.WriteError;
                total_currently_found += 1;
                if (additional_data.entity_count_to_find != 0 and total_currently_found >= additional_data.entity_count_to_find) break :blk;
            }
        }

        writer.writeAll("]") catch return FileEngineError.WriteError;
    }

    fn writeArray(data: *zid.Data, writer: anytype, datatype: ?DataType) FileEngineError!void {
        writer.writeByte('[') catch return FileEngineError.WriteError;
        var iter = zid.ArrayIterator.init(data) catch return FileEngineError.ZipponDataError;
        switch (data.*) {
            .IntArray => while (iter.next()) |v| writer.print("{d}, ", .{v.Int}) catch return FileEngineError.WriteError,
            .FloatArray => while (iter.next()) |v| writer.print("{d}", .{v.Float}) catch return FileEngineError.WriteError,
            .StrArray => while (iter.next()) |v| writer.print("\"{s}\"", .{v.Str}) catch return FileEngineError.WriteError,
            .UUIDArray => while (iter.next()) |v| writer.print("\"{s}\"", .{UUID.format_bytes(v.UUID)}) catch return FileEngineError.WriteError,
            .BoolArray => while (iter.next()) |v| writer.print("{any}", .{v.Bool}) catch return FileEngineError.WriteError,
            .UnixArray => {
                while (iter.next()) |v| {
                    const datetime = DateTime.initUnix(v.Unix);
                    writer.writeByte('"') catch return FileEngineError.WriteError;
                    switch (datatype.?) {
                        .date => datetime.format("YYYY/MM/DD", writer) catch return FileEngineError.WriteError,
                        .time => datetime.format("HH:mm:ss.SSSS", writer) catch return FileEngineError.WriteError,
                        .datetime => datetime.format("YYYY/MM/DD-HH:mm:ss.SSSS", writer) catch return FileEngineError.WriteError,
                        else => unreachable,
                    }
                    writer.writeAll("\", ") catch return FileEngineError.WriteError;
                }
            },
            else => unreachable,
        }
        writer.writeByte(']') catch return FileEngineError.WriteError;
    }

    // --------------------Change existing files--------------------

    // TODO: Make it in batch too
    pub fn writeEntity(
        self: *FileEngine,
        struct_name: []const u8,
        map: std.StringHashMap([]const u8),
        buffer: *std.ArrayList(u8),
    ) FileEngineError!void {
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

        var data_writer = zid.DataWriter.init(path, null) catch return FileEngineError.ZipponDataError;
        data_writer.write(data) catch return FileEngineError.ZipponDataError;
        data_writer.flush() catch return FileEngineError.ZipponDataError;

        var writer = buffer.writer();
        writer.writeByte('{') catch return FileEngineError.WriteError;
        writer.print("\"{s}\"", .{uuid.format_uuid()}) catch return FileEngineError.WriteError;
        writer.writeAll("}, ") catch return FileEngineError.WriteError;
    }

    pub fn updateEntities(
        self: *FileEngine,
        struct_name: []const u8,
        filter: ?Filter,
        buffer: *std.ArrayList(u8),
        additional_data: *AdditionalData,
    ) FileEngineError!void {
        const sstruct = try self.structName2SchemaStruct(struct_name);
        const max_file_index = try self.maxFileIndex(sstruct.name);
        var total_currently_found: usize = 0;

        var path_buff = std.fmt.allocPrint(
            self.allocator,
            "{s}/DATA/{s}",
            .{ self.path_to_ZipponDB_dir, sstruct.name },
        ) catch return FileEngineError.MemoryError;
        defer self.allocator.free(path_buff);
        const dir = std.fs.cwd().openDir(path_buff, .{}) catch return FileEngineError.CantOpenDir;

        var writer = buffer.writer();
        writer.writeAll("[") catch return FileEngineError.WriteError;
        for (0..(max_file_index + 1)) |file_index| { // TODO: Multi thread that
            self.allocator.free(path_buff);
            path_buff = std.fmt.allocPrint(self.allocator, "{d}.zid", .{file_index}) catch return FileEngineError.MemoryError;

            var iter = zid.DataIterator.init(self.allocator, path_buff, dir, sstruct.zid_schema) catch return FileEngineError.ZipponDataError;
            defer iter.deinit();

            const new_path_buff = std.fmt.allocPrint(self.allocator, "{d}.zid.new", .{file_index}) catch return FileEngineError.MemoryError;
            defer self.allocator.free(new_path_buff);

            zid.createFile(new_path_buff, dir) catch return FileEngineError.ZipponDataError;
            var new_writer = zid.DataWriter.init(new_path_buff, dir) catch return FileEngineError.ZipponDataError;
            defer new_writer.deinit();

            blk: while (iter.next() catch return FileEngineError.ZipponDataError) |row| {
                if (filter != null) if (!filter.?.evaluate(row)) continue;

                new_writer.write(row) catch return FileEngineError.WriteError;
                writer.writeByte('{') catch return FileEngineError.WriteError;
                writer.print("\"{s}\"", .{UUID.format_bytes(row[0].UUID)}) catch return FileEngineError.WriteError;
                writer.writeAll("}, ") catch return FileEngineError.WriteError;
                total_currently_found += 1;
                if (additional_data.entity_count_to_find != 0 and total_currently_found >= additional_data.entity_count_to_find) break :blk;
            }

            new_writer.flush() catch return FileEngineError.ZipponDataError;
            dir.deleteFile(path_buff) catch return FileEngineError.DeleteFileError;
            dir.rename(new_path_buff, path_buff) catch return FileEngineError.RenameFileError;
        }

        writer.writeAll("]") catch return FileEngineError.WriteError;
    }

    /// Will delete all entity based on the filter. Will also write a JSON format list of all UUID deleted into the buffer
    pub fn deleteEntities(
        self: *FileEngine,
        struct_name: []const u8,
        filter: ?Filter,
        buffer: *std.ArrayList(u8),
        additional_data: *AdditionalData,
    ) FileEngineError!void {
        const sstruct = try self.structName2SchemaStruct(struct_name);
        const max_file_index = try self.maxFileIndex(sstruct.name);
        var total_currently_found: usize = 0;

        var path_buff = std.fmt.allocPrint(
            self.allocator,
            "{s}/DATA/{s}",
            .{ self.path_to_ZipponDB_dir, sstruct.name },
        ) catch return FileEngineError.MemoryError;
        defer self.allocator.free(path_buff);
        const dir = std.fs.cwd().openDir(path_buff, .{}) catch return FileEngineError.CantOpenDir;

        var writer = buffer.writer();
        writer.writeAll("[") catch return FileEngineError.WriteError;
        for (0..(max_file_index + 1)) |file_index| { // TODO: Multi thread that
            self.allocator.free(path_buff);
            path_buff = std.fmt.allocPrint(self.allocator, "{d}.zid", .{file_index}) catch return FileEngineError.MemoryError;

            var iter = zid.DataIterator.init(self.allocator, path_buff, dir, sstruct.zid_schema) catch return FileEngineError.ZipponDataError;
            defer iter.deinit();

            const new_path_buff = std.fmt.allocPrint(self.allocator, "{d}.zid.new", .{file_index}) catch return FileEngineError.MemoryError;
            defer self.allocator.free(new_path_buff);

            zid.createFile(new_path_buff, dir) catch return FileEngineError.ZipponDataError;
            var new_writer = zid.DataWriter.init(new_path_buff, dir) catch return FileEngineError.ZipponDataError;
            defer new_writer.deinit();

            blk: while (iter.next() catch return FileEngineError.ZipponDataError) |row| {
                if (filter != null) if (!filter.?.evaluate(row)) {
                    writer.writeByte('{') catch return FileEngineError.WriteError;
                    writer.print("\"{s}\"", .{UUID.format_bytes(row[0].UUID)}) catch return FileEngineError.WriteError;
                    writer.writeAll("}, ") catch return FileEngineError.WriteError;
                    total_currently_found += 1;
                    if (additional_data.entity_count_to_find != 0 and total_currently_found >= additional_data.entity_count_to_find) break :blk;
                } else {
                    new_writer.write(row) catch return FileEngineError.WriteError;
                };
            }

            new_writer.flush() catch return FileEngineError.ZipponDataError;
            dir.deleteFile(path_buff) catch return FileEngineError.DeleteFileError;
            dir.rename(new_path_buff, path_buff) catch return FileEngineError.RenameFileError;
        }

        writer.writeAll("]") catch return FileEngineError.WriteError;
    }

    // --------------------ZipponData utils--------------------

    // Function that take a map from the parseNewData and return an ordered array of Data
    pub fn orderedNewData(self: *FileEngine, allocator: Allocator, struct_name: []const u8, map: std.StringHashMap([]const u8)) FileEngineError![]const zid.Data {
        const members = try self.structName2structMembers(struct_name);
        const types = try self.structName2DataType(struct_name);

        var datas = allocator.alloc(zid.Data, (members.len + 1)) catch return FileEngineError.MemoryError;

        const new_uuid = UUID.init();
        datas[0] = zid.Data.initUUID(new_uuid.bytes);

        for (members, types, 1..) |member, dt, i| {
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
                    const array = s2t.parseArrayInt(allocator, map.get(member).?) catch return FileEngineError.MemoryError;
                    defer allocator.free(array);

                    datas[i] = zid.Data.initIntArray(zid.allocEncodArray.Int(allocator, array) catch return FileEngineError.AllocEncodError);
                },
                .float_array => {
                    const array = s2t.parseArrayFloat(allocator, map.get(member).?) catch return FileEngineError.MemoryError;
                    defer allocator.free(array);

                    datas[i] = zid.Data.initFloatArray(zid.allocEncodArray.Float(allocator, array) catch return FileEngineError.AllocEncodError);
                },
                .str_array => {
                    const array = s2t.parseArrayStr(allocator, map.get(member).?) catch return FileEngineError.MemoryError;
                    defer allocator.free(array);

                    datas[i] = zid.Data.initStrArray(zid.allocEncodArray.Str(allocator, array) catch return FileEngineError.AllocEncodError);
                },
                .bool_array => {
                    const array = s2t.parseArrayBool(allocator, map.get(member).?) catch return FileEngineError.MemoryError;
                    defer allocator.free(array);

                    datas[i] = zid.Data.initFloatArray(zid.allocEncodArray.Bool(allocator, array) catch return FileEngineError.AllocEncodError);
                },
                .link_array => {
                    const array = s2t.parseArrayUUIDBytes(allocator, map.get(member).?) catch return FileEngineError.MemoryError;
                    defer allocator.free(array);

                    datas[i] = zid.Data.initUUIDArray(zid.allocEncodArray.UUID(allocator, array) catch return FileEngineError.AllocEncodError);
                },
                .date_array => {
                    const array = s2t.parseArrayDateUnix(allocator, map.get(member).?) catch return FileEngineError.MemoryError;
                    defer allocator.free(array);

                    datas[i] = zid.Data.initUnixArray(zid.allocEncodArray.Unix(allocator, array) catch return FileEngineError.AllocEncodError);
                },
                .time_array => {
                    const array = s2t.parseArrayTimeUnix(allocator, map.get(member).?) catch return FileEngineError.MemoryError;
                    defer allocator.free(array);

                    datas[i] = zid.Data.initUnixArray(zid.allocEncodArray.Unix(allocator, array) catch return FileEngineError.AllocEncodError);
                },
                .datetime_array => {
                    const array = s2t.parseArrayDatetimeUnix(allocator, map.get(member).?) catch return FileEngineError.MemoryError;
                    defer allocator.free(array);

                    datas[i] = zid.Data.initUnixArray(zid.allocEncodArray.Unix(allocator, array) catch return FileEngineError.AllocEncodError);
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
        var i: usize = 1; // Start at 1 because there is the id

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

        return self.struct_array[i].members;
    }

    pub fn structName2SchemaStruct(self: *FileEngine, struct_name: []const u8) FileEngineError!SchemaStruct {
        var i: usize = 0;

        while (i < self.struct_array.len) : (i += 1) if (std.mem.eql(u8, self.struct_array[i].name, struct_name)) break;

        if (i == self.struct_array.len) {
            return FileEngineError.StructNotFound;
        }

        return self.struct_array[i];
    }

    pub fn structName2DataType(self: *FileEngine, struct_name: []const u8) FileEngineError![]const DataType {
        var i: u16 = 0;

        while (i < self.struct_array.len) : (i += 1) {
            if (std.mem.eql(u8, self.struct_array[i].name, struct_name)) break;
        }

        if (i == self.struct_array.len and !std.mem.eql(u8, self.struct_array[i].name, struct_name)) {
            return FileEngineError.StructNotFound;
        }

        return self.struct_array[i].types;
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
