const std = @import("std");
const utils = @import("stuffs/utils.zig");
const dtype = @import("dtype");
const s2t = dtype.s2t;
const zid = @import("ZipponData");
const time = std.time;
const U64 = std.atomic.Value(u64);
const Pool = std.Thread.Pool;
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

const ZipponError = @import("stuffs/errors.zig").ZipponError;
const FileEngineError = @import("stuffs/errors.zig").FileEngineError;

const config = @import("config.zig");
const BUFFER_SIZE = config.BUFFER_SIZE;
const MAX_FILE_SIZE = config.MAX_FILE_SIZE;
const CSV_DELIMITER = config.CSV_DELIMITER;
const RESET_LOG_AT_RESTART = config.RESET_LOG_AT_RESTART;
const CPU_CORE = config.CPU_CORE;

const log = std.log.scoped(.fileEngine);

/// Manage everything that is relate to read or write in files
/// Or even get stats, whatever. If it touch files, it's here
/// TODO: Keep all struct dir in a haspmap so I dont need to use an allocPrint everytime
pub const FileEngine = struct {
    allocator: Allocator,
    path_to_ZipponDB_dir: []const u8,
    null_terminated_schema_buff: [:0]u8,
    struct_array: []SchemaStruct,

    pub fn init(allocator: Allocator, path: []const u8) ZipponError!FileEngine {
        const path_to_ZipponDB_dir = path;

        var schema_buf = allocator.alloc(u8, BUFFER_SIZE) catch return FileEngineError.MemoryError; // TODO: Use a list
        defer allocator.free(schema_buf);

        const len: usize = FileEngine.readSchemaFile(path_to_ZipponDB_dir, schema_buf) catch 0;
        const null_terminated_schema_buff = allocator.dupeZ(u8, schema_buf[0..len]) catch return FileEngineError.MemoryError;
        errdefer allocator.free(null_terminated_schema_buff);

        var toker = SchemaTokenizer.init(null_terminated_schema_buff);
        var parser = SchemaParser.init(&toker, allocator);

        var struct_array = std.ArrayList(SchemaStruct).init(allocator);
        parser.parse(&struct_array) catch return FileEngineError.SchemaNotConform;

        return FileEngine{
            .allocator = allocator,
            .path_to_ZipponDB_dir = path_to_ZipponDB_dir,
            .null_terminated_schema_buff = null_terminated_schema_buff,
            .struct_array = struct_array.toOwnedSlice() catch return FileEngineError.MemoryError,
        };

        // try file_engine.populateAllUUIDToFileIndexMap();

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

    // For all struct in shema, add the UUID/index_file into the map
    pub fn populateAllUUIDToFileIndexMap(self: *FileEngine) ZipponError!void {
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

    // --------------------Other--------------------

    pub fn readSchemaFile(sub_path: []const u8, buffer: []u8) ZipponError!usize {
        const file = try utils.printOpenFile("{s}/schema", .{sub_path}, .{});
        defer file.close();

        const len = file.readAll(buffer) catch return FileEngineError.ReadError;
        return len;
    }

    pub fn writeDbMetrics(self: *FileEngine, buffer: *std.ArrayList(u8)) ZipponError!void {
        const main_dir = std.fs.cwd().openDir(self.path_to_ZipponDB_dir, .{ .iterate = true }) catch return FileEngineError.CantOpenDir;

        const writer = buffer.writer();
        writer.print("Database path: {s}\n", .{self.path_to_ZipponDB_dir}) catch return FileEngineError.WriteError;
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
            // FIXME: This is not really MB
            writer.print("  {s}: {d:.}Mb {d} entities\n", .{
                entry.name,
                @as(f64, @floatFromInt(size)) / 1e6,
                try self.getNumberOfEntity(entry.name),
            }) catch return FileEngineError.WriteError;
        }
    }

    // --------------------Init folder and files--------------------

    /// Create the main folder. Including DATA, LOG and BACKUP
    pub fn checkAndCreateDirectories(self: *FileEngine) ZipponError!void {
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
    pub fn initDataFolder(self: *FileEngine, path_to_schema_file: []const u8) ZipponError!void {
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

    /// Use a struct name to populate a list with all UUID of this struct
    pub fn getNumberOfEntity(self: *FileEngine, struct_name: []const u8) ZipponError!usize {
        const sstruct = try self.structName2SchemaStruct(struct_name);
        const max_file_index = try self.maxFileIndex(sstruct.name);
        var count: usize = 0;

        const dir = try utils.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, sstruct.name }, .{});

        for (0..(max_file_index + 1)) |i| {
            const path_buff = std.fmt.allocPrint(self.allocator, "{d}.zid", .{i}) catch return FileEngineError.MemoryError;
            defer self.allocator.free(path_buff);

            var iter = zid.DataIterator.init(self.allocator, path_buff, dir, sstruct.zid_schema) catch return FileEngineError.ZipponDataError;
            defer iter.deinit();

            while (iter.next() catch return FileEngineError.ZipponDataError) |_| count += 1;
        }

        return count;
    }

    /// Use a struct name to populate a list with all UUID of this struct
    pub fn getAllUUIDList(self: *FileEngine, struct_name: []const u8, uuid_list: *std.ArrayList(UUID)) ZipponError!void {
        const sstruct = try self.structName2SchemaStruct(struct_name);
        const max_file_index = try self.maxFileIndex(sstruct.name);

        const dir = try utils.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, sstruct.name }, .{});

        for (0..(max_file_index + 1)) |i| {
            const path_buff = std.fmt.allocPrint(self.allocator, "{d}.zid", .{i}) catch return FileEngineError.MemoryError;
            defer self.allocator.free(path_buff);

            var iter = zid.DataIterator.init(self.allocator, path_buff, dir, sstruct.zid_schema) catch return FileEngineError.ZipponDataError;
            defer iter.deinit();

            while (iter.next() catch return FileEngineError.ZipponDataError) |row| uuid_list.append(UUID{ .bytes = row[0].UUID }) catch return FileEngineError.MemoryError;
        }
    }

    /// Take a condition and an array of UUID and fill the array with all UUID that match the condition
    pub fn getUUIDListUsingFilter(self: *FileEngine, struct_name: []const u8, filter: Filter, uuid_list: *std.ArrayList(UUID)) ZipponError!void {
        const sstruct = try self.structName2SchemaStruct(struct_name);
        const max_file_index = try self.maxFileIndex(sstruct.name);

        const dir = try utils.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, sstruct.name }, .{});

        for (0..(max_file_index + 1)) |i| {
            const path_buff = std.fmt.allocPrint(self.allocator, "{d}.zid", .{i}) catch return FileEngineError.MemoryError;
            defer self.allocator.free(path_buff);

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
        writer: anytype,
        additional_data: *AdditionalData,
    ) ZipponError!void {
        const sstruct = try self.structName2SchemaStruct(struct_name);
        const max_file_index = try self.maxFileIndex(sstruct.name);

        // If there is no member to find, that mean we need to return all members, so let's populate additional data with all of them
        if (additional_data.member_to_find.items.len == 0) {
            additional_data.populateWithEverything(self.allocator, sstruct.members) catch return FileEngineError.MemoryError;
        }

        // Open the dir that contain all files
        const dir = try utils.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, sstruct.name }, .{ .access_sub_paths = false });

        // Multi thread stuffs
        var total_entity_found: U64 = U64.init(0);
        var ended_count: U64 = U64.init(0);
        var error_count: U64 = U64.init(0);

        var thread_safe_arena: std.heap.ThreadSafeAllocator = .{
            .child_allocator = self.allocator,
        };
        const arena = thread_safe_arena.allocator();

        // TODO: Put that in the file engine members, so I dont need to init the Pool every time
        var thread_pool: Pool = undefined;
        thread_pool.init(Pool.Options{
            .allocator = arena, // this is an arena allocator from `std.heap.ArenaAllocator`
            .n_jobs = CPU_CORE, // optional, by default the number of CPUs available
        }) catch return FileEngineError.ThreadError;
        defer thread_pool.deinit();

        // Do one array and writer for each thread otherwise then create error by writing at the same time
        // Maybe use fixed lenght buffer for speed here
        var thread_writer_list = self.allocator.alloc(std.ArrayList(u8), max_file_index + 1) catch return FileEngineError.MemoryError;
        defer {
            for (thread_writer_list) |list| list.deinit();
            self.allocator.free(thread_writer_list);
        }

        // Maybe do one buffer per files ?
        var data_buffer: [BUFFER_SIZE]u8 = undefined;
        var fa = std.heap.FixedBufferAllocator.init(&data_buffer);
        defer fa.reset();
        const allocator = fa.allocator();

        // Start parsing all file in multiple thread
        for (0..(max_file_index + 1)) |file_index| {
            thread_writer_list[file_index] = std.ArrayList(u8).init(allocator);

            thread_pool.spawn(parseEntitiesOneFile, .{
                thread_writer_list[file_index].writer(),
                file_index,
                dir,
                sstruct.zid_schema,
                filter,
                additional_data,
                try self.structName2DataType(struct_name),
                &total_entity_found,
                &ended_count,
                &error_count,
            }) catch return FileEngineError.ThreadError;
        }

        // Wait for all thread to either finish or return an error
        while ((ended_count.load(.acquire) + error_count.load(.acquire)) < max_file_index + 1) {
            std.time.sleep(10_000_000); // Check every 10ms
        }

        // Append all writer to each other
        writer.writeByte('[') catch return FileEngineError.WriteError;
        for (thread_writer_list) |list| writer.writeAll(list.items) catch return FileEngineError.WriteError;
        writer.writeByte(']') catch return FileEngineError.WriteError;
    }

    fn parseEntitiesOneFile(
        writer: anytype,
        file_index: u64,
        dir: std.fs.Dir,
        zid_schema: []zid.DType,
        filter: ?Filter,
        additional_data: *AdditionalData,
        data_types: []const DataType,
        total_entity_found: *U64,
        ended_count: *U64,
        error_count: *U64,
    ) void {
        var data_buffer: [BUFFER_SIZE]u8 = undefined;
        var fa = std.heap.FixedBufferAllocator.init(&data_buffer);
        defer fa.reset();
        const allocator = fa.allocator();

        var path_buffer: [128]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buffer, "{d}.zid", .{file_index}) catch |err| {
            logErrorAndIncrementCount("Error creating file path", err, error_count);
            return;
        };

        var iter = zid.DataIterator.init(allocator, path, dir, zid_schema) catch |err| {
            logErrorAndIncrementCount("Error initializing DataIterator", err, error_count);
            return;
        };

        while (iter.next() catch return) |row| {
            if (filter) |f| if (!f.evaluate(row)) continue;

            if (writeEntity(writer, row, additional_data, data_types)) |_| {
                if (incrementAndCheckLimit(total_entity_found, additional_data.entity_count_to_find)) break;
            } else |err| {
                logErrorAndIncrementCount("Error writing entity", err, error_count);
                return;
            }
        }

        _ = ended_count.fetchAdd(1, .acquire);
    }

    fn writeEntity(
        writer: anytype,
        row: []zid.Data,
        additional_data: *AdditionalData,
        data_types: []const DataType,
    ) !void {
        try writer.writeByte('{');
        for (additional_data.member_to_find.items) |member| {
            try writer.print("{s}: ", .{member.name});
            try writeValue(writer, row[member.index], data_types[member.index]);
            try writer.writeAll(", ");
        }
        try writer.writeAll("}, ");
    }

    fn writeValue(writer: anytype, value: zid.Data, data_type: DataType) !void {
        switch (value) {
            .Float => |v| try writer.print("{d}", .{v}),
            .Int => |v| try writer.print("{d}", .{v}),
            .Str => |v| try writer.print("\"{s}\"", .{v}),
            .UUID => |v| try writer.print("\"{s}\"", .{UUID.format_bytes(v)}),
            .Bool => |v| try writer.print("{any}", .{v}),
            .Unix => |v| try writeDateTime(writer, v, data_type),
            .IntArray, .FloatArray, .StrArray, .UUIDArray, .BoolArray, .UnixArray => try writeArray(writer, value, data_type),
        }
    }

    fn writeDateTime(writer: anytype, unix_time: u64, data_type: DataType) !void {
        const datetime = DateTime.initUnix(unix_time);
        try writer.writeByte('"');
        switch (data_type) {
            .date => try datetime.format("YYYY/MM/DD", writer),
            .time => try datetime.format("HH:mm:ss.SSSS", writer),
            .datetime => try datetime.format("YYYY/MM/DD-HH:mm:ss.SSSS", writer),
            else => unreachable,
        }
        try writer.writeByte('"');
    }

    fn writeArray(writer: anytype, data: zid.Data, data_type: DataType) ZipponError!void {
        writer.writeByte('[') catch return FileEngineError.WriteError;
        var iter = zid.ArrayIterator.init(data) catch return FileEngineError.ZipponDataError;
        switch (data) {
            .IntArray => while (iter.next()) |v| writer.print("{d}, ", .{v.Int}) catch return FileEngineError.WriteError,
            .FloatArray => while (iter.next()) |v| writer.print("{d}", .{v.Float}) catch return FileEngineError.WriteError,
            .StrArray => while (iter.next()) |v| writer.print("\"{s}\"", .{v.Str}) catch return FileEngineError.WriteError,
            .UUIDArray => while (iter.next()) |v| writer.print("\"{s}\"", .{UUID.format_bytes(v.UUID)}) catch return FileEngineError.WriteError,
            .BoolArray => while (iter.next()) |v| writer.print("{any}", .{v.Bool}) catch return FileEngineError.WriteError,
            .UnixArray => {
                while (iter.next()) |v| {
                    const datetime = DateTime.initUnix(v.Unix);
                    writer.writeByte('"') catch return FileEngineError.WriteError;
                    switch (data_type) {
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

    fn incrementAndCheckLimit(counter: *U64, limit: u64) bool {
        const new_count = counter.fetchAdd(1, .monotonic) + 1;
        return limit != 0 and new_count >= limit;
    }

    fn logErrorAndIncrementCount(message: []const u8, err: anyerror, error_count: *U64) void {
        log.err("{s}: {any}", .{ message, err });
        _ = error_count.fetchAdd(1, .acquire);
    }

    // --------------------Change existing files--------------------

    // TODO: Make it in batch too
    pub fn addEntity(
        self: *FileEngine,
        struct_name: []const u8,
        map: std.StringHashMap([]const u8),
        writer: anytype,
        n: usize,
    ) ZipponError!void {
        const file_index = try self.getFirstUsableIndexFile(struct_name);

        const path = std.fmt.allocPrint(
            self.allocator,
            "{s}/DATA/{s}/{d}.zid",
            .{ self.path_to_ZipponDB_dir, struct_name, file_index },
        ) catch return FileEngineError.MemoryError;
        defer self.allocator.free(path);

        var data_buffer: [BUFFER_SIZE]u8 = undefined;
        var fa = std.heap.FixedBufferAllocator.init(&data_buffer);
        defer fa.reset();
        const data_allocator = fa.allocator();

        const data = try self.orderedNewData(data_allocator, struct_name, map);

        var data_writer = zid.DataWriter.init(path, null) catch return FileEngineError.ZipponDataError;
        defer data_writer.deinit();

        for (0..n) |_| data_writer.write(data) catch return FileEngineError.ZipponDataError;
        data_writer.flush() catch return FileEngineError.ZipponDataError;

        writer.print("[\"{s}\"]", .{UUID.format_bytes(data[0].UUID)}) catch return FileEngineError.WriteError;
    }

    pub fn updateEntities(
        self: *FileEngine,
        struct_name: []const u8,
        filter: ?Filter,
        map: std.StringHashMap([]const u8),
        writer: anytype,
        additional_data: *AdditionalData,
    ) ZipponError!void {
        const sstruct = try self.structName2SchemaStruct(struct_name);
        const max_file_index = try self.maxFileIndex(sstruct.name);
        var total_currently_found: usize = 0;

        const dir = try utils.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, sstruct.name }, .{});

        var new_data_buff = self.allocator.alloc(zid.Data, try self.numberOfMemberInStruct(struct_name)) catch return FileEngineError.MemoryError;
        defer self.allocator.free(new_data_buff);

        // Add the new data
        for (try self.structName2structMembers(struct_name), 0..) |member, i| {
            if (!map.contains(member)) continue;

            const dt = try self.memberName2DataType(struct_name, member);
            new_data_buff[i] = try string2Data(self.allocator, dt, map.get(member).?);
        }

        writer.writeByte('[') catch return FileEngineError.WriteError;
        for (0..(max_file_index + 1)) |file_index| { // TODO: Multi thread that
            if (additional_data.entity_count_to_find != 0 and total_currently_found >= additional_data.entity_count_to_find) break;

            const path_buff = std.fmt.allocPrint(self.allocator, "{d}.zid", .{file_index}) catch return FileEngineError.MemoryError;
            defer self.allocator.free(path_buff);

            var iter = zid.DataIterator.init(self.allocator, path_buff, dir, sstruct.zid_schema) catch return FileEngineError.ZipponDataError;
            defer iter.deinit();

            const new_path_buff = std.fmt.allocPrint(self.allocator, "{d}.zid.new", .{file_index}) catch return FileEngineError.MemoryError;
            defer self.allocator.free(new_path_buff);

            zid.createFile(new_path_buff, dir) catch return FileEngineError.ZipponDataError;
            var new_writer = zid.DataWriter.init(new_path_buff, dir) catch return FileEngineError.ZipponDataError;
            defer new_writer.deinit();

            while (iter.next() catch return FileEngineError.ZipponDataError) |row| {
                if (filter == null or filter.?.evaluate(row)) {
                    // Add the unchanged Data in the new_data_buff
                    new_data_buff[0] = row[0];
                    for (try self.structName2structMembers(struct_name), 0..) |member, i| {
                        if (map.contains(member)) continue;
                        new_data_buff[i] = row[i];
                    }

                    new_writer.write(new_data_buff) catch return FileEngineError.WriteError;
                    writer.writeByte('{') catch return FileEngineError.WriteError;
                    writer.print("\"{s}\"", .{UUID.format_bytes(row[0].UUID)}) catch return FileEngineError.WriteError;
                    writer.writeAll("},") catch return FileEngineError.WriteError;
                    total_currently_found += 1;
                } else {
                    new_writer.write(row) catch return FileEngineError.WriteError;
                }

                if (additional_data.entity_count_to_find != 0 and total_currently_found >= additional_data.entity_count_to_find) break;
            }

            writer.writeByte(']') catch return FileEngineError.WriteError;
            new_writer.flush() catch return FileEngineError.ZipponDataError;
            dir.deleteFile(path_buff) catch return FileEngineError.DeleteFileError;
            dir.rename(new_path_buff, path_buff) catch return FileEngineError.RenameFileError;
        }

        for (try self.structName2structMembers(struct_name), 1..) |member, i| {
            if (!map.contains(member)) continue;

            switch (new_data_buff[i]) {
                .IntArray => self.allocator.free(new_data_buff[i].IntArray),
                .FloatArray => self.allocator.free(new_data_buff[i].FloatArray),
                .UnixArray => self.allocator.free(new_data_buff[i].UnixArray),
                .BoolArray => self.allocator.free(new_data_buff[i].BoolArray),
                .StrArray => self.allocator.free(new_data_buff[i].StrArray),
                .UUIDArray => self.allocator.free(new_data_buff[i].UUIDArray),
                else => continue,
            }
        }
    }

    /// Will delete all entity based on the filter. Will also write a JSON format list of all UUID deleted into the buffer
    pub fn deleteEntities(
        self: *FileEngine,
        struct_name: []const u8,
        filter: ?Filter,
        writer: anytype,
        additional_data: *AdditionalData,
    ) ZipponError!void {
        const sstruct = try self.structName2SchemaStruct(struct_name);
        const max_file_index = try self.maxFileIndex(sstruct.name);
        var total_currently_found: usize = 0;

        const dir = try utils.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, sstruct.name }, .{});

        writer.writeByte('[') catch return FileEngineError.WriteError;
        for (0..(max_file_index + 1)) |file_index| { // TODO: Multi thread that
            const path_buff = std.fmt.allocPrint(self.allocator, "{d}.zid", .{file_index}) catch return FileEngineError.MemoryError;
            defer self.allocator.free(path_buff);

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
                    writer.writeAll("},") catch return FileEngineError.WriteError;
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

        writer.writeByte(']') catch return FileEngineError.WriteError;
    }

    // --------------------ZipponData utils--------------------

    fn string2Data(allocator: Allocator, dt: DataType, value: []const u8) ZipponError!zid.Data {
        switch (dt) {
            .int => return zid.Data.initInt(s2t.parseInt(value)),
            .float => return zid.Data.initFloat(s2t.parseFloat(value)),
            .bool => return zid.Data.initBool(s2t.parseBool(value)),
            .date => return zid.Data.initUnix(s2t.parseDate(value).toUnix()),
            .time => return zid.Data.initUnix(s2t.parseTime(value).toUnix()),
            .datetime => return zid.Data.initUnix(s2t.parseDatetime(value).toUnix()),
            .str => return zid.Data.initStr(value),
            .link, .self => {
                const uuid = UUID.parse(value) catch return FileEngineError.InvalidUUID;
                return zid.Data{ .UUID = uuid.bytes };
            },
            .int_array => {
                const array = s2t.parseArrayInt(allocator, value) catch return FileEngineError.MemoryError;
                defer allocator.free(array);

                return zid.Data.initIntArray(zid.allocEncodArray.Int(allocator, array) catch return FileEngineError.AllocEncodError);
            },
            .float_array => {
                const array = s2t.parseArrayFloat(allocator, value) catch return FileEngineError.MemoryError;
                defer allocator.free(array);

                return zid.Data.initFloatArray(zid.allocEncodArray.Float(allocator, array) catch return FileEngineError.AllocEncodError);
            },
            .str_array => {
                const array = s2t.parseArrayStr(allocator, value) catch return FileEngineError.MemoryError;
                defer allocator.free(array);

                return zid.Data.initStrArray(zid.allocEncodArray.Str(allocator, array) catch return FileEngineError.AllocEncodError);
            },
            .bool_array => {
                const array = s2t.parseArrayBool(allocator, value) catch return FileEngineError.MemoryError;
                defer allocator.free(array);

                return zid.Data.initFloatArray(zid.allocEncodArray.Bool(allocator, array) catch return FileEngineError.AllocEncodError);
            },
            .link_array => {
                const array = s2t.parseArrayUUIDBytes(allocator, value) catch return FileEngineError.MemoryError;
                defer allocator.free(array);

                return zid.Data.initUUIDArray(zid.allocEncodArray.UUID(allocator, array) catch return FileEngineError.AllocEncodError);
            },
            .date_array => {
                const array = s2t.parseArrayDateUnix(allocator, value) catch return FileEngineError.MemoryError;
                defer allocator.free(array);

                return zid.Data.initUnixArray(zid.allocEncodArray.Unix(allocator, array) catch return FileEngineError.AllocEncodError);
            },
            .time_array => {
                const array = s2t.parseArrayTimeUnix(allocator, value) catch return FileEngineError.MemoryError;
                defer allocator.free(array);

                return zid.Data.initUnixArray(zid.allocEncodArray.Unix(allocator, array) catch return FileEngineError.AllocEncodError);
            },
            .datetime_array => {
                const array = s2t.parseArrayDatetimeUnix(allocator, value) catch return FileEngineError.MemoryError;
                defer allocator.free(array);

                return zid.Data.initUnixArray(zid.allocEncodArray.Unix(allocator, array) catch return FileEngineError.AllocEncodError);
            },
        }
    }

    /// Take a map from the parseNewData and return an ordered array of Data to be use in a DataWriter
    /// TODO: Optimize
    fn orderedNewData(
        self: *FileEngine,
        allocator: Allocator,
        struct_name: []const u8,
        map: std.StringHashMap([]const u8),
    ) ZipponError![]zid.Data {
        const members = try self.structName2structMembers(struct_name);
        const types = try self.structName2DataType(struct_name);

        var datas = allocator.alloc(zid.Data, (members.len)) catch return FileEngineError.MemoryError;

        const new_uuid = UUID.init();
        datas[0] = zid.Data.initUUID(new_uuid.bytes);

        for (members, types, 0..) |member, dt, i| {
            if (i == 0) continue; // Skip the id
            datas[i] = try string2Data(allocator, dt, map.get(member).?);
        }

        return datas;
    }

    // --------------------Schema utils--------------------

    /// Get the index of the first file that is bellow the size limit. If not found, create a new file
    /// TODO: Need some serious speed up. I should keep in memory a file->size as a hashmap and use that instead
    fn getFirstUsableIndexFile(self: FileEngine, struct_name: []const u8) ZipponError!usize {
        var member_dir = try utils.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, struct_name }, .{ .iterate = true });
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

        const path = std.fmt.allocPrint(
            self.allocator,
            "{s}/DATA/{s}/{d}.zid",
            .{ self.path_to_ZipponDB_dir, struct_name, i },
        ) catch return FileEngineError.MemoryError;
        defer self.allocator.free(path);

        zid.createFile(path, null) catch return FileEngineError.ZipponDataError;

        return i;
    }

    /// Iterate over all file of a struct and return the index of the last file.
    /// E.g. a struct with 0.csv and 1.csv it return 1.
    fn maxFileIndex(self: FileEngine, struct_name: []const u8) ZipponError!usize {
        var member_dir = try utils.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, struct_name }, .{ .iterate = true });
        defer member_dir.close();

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
    pub fn memberName2DataType(self: *FileEngine, struct_name: []const u8, member_name: []const u8) ZipponError!DataType {
        var i: usize = 0;

        for (try self.structName2structMembers(struct_name)) |mn| {
            const dtypes = try self.structName2DataType(struct_name);
            if (std.mem.eql(u8, mn, member_name)) return dtypes[i];
            i += 1;
        }

        return FileEngineError.MemberNotFound;
    }

    pub fn memberName2DataIndex(self: *FileEngine, struct_name: []const u8, member_name: []const u8) ZipponError!usize {
        var i: usize = 0;

        for (try self.structName2structMembers(struct_name)) |mn| {
            if (std.mem.eql(u8, mn, member_name)) return i;
            i += 1;
        }

        return FileEngineError.MemberNotFound;
    }

    /// Get the list of all member name for a struct name
    pub fn structName2structMembers(self: *FileEngine, struct_name: []const u8) ZipponError![][]const u8 {
        var i: usize = 0;

        while (i < self.struct_array.len) : (i += 1) if (std.mem.eql(u8, self.struct_array[i].name, struct_name)) break;

        if (i == self.struct_array.len) {
            return FileEngineError.StructNotFound;
        }

        return self.struct_array[i].members;
    }

    pub fn structName2SchemaStruct(self: *FileEngine, struct_name: []const u8) ZipponError!SchemaStruct {
        var i: usize = 0;

        while (i < self.struct_array.len) : (i += 1) if (std.mem.eql(u8, self.struct_array[i].name, struct_name)) break;

        if (i == self.struct_array.len) {
            return FileEngineError.StructNotFound;
        }

        return self.struct_array[i];
    }

    pub fn structName2DataType(self: *FileEngine, struct_name: []const u8) ZipponError![]const DataType {
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
    fn numberOfMemberInStruct(self: *FileEngine, struct_name: []const u8) ZipponError!usize {
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
    pub fn isMemberNameInStruct(self: *FileEngine, struct_name: []const u8, member_name: []const u8) ZipponError!bool {
        for (try self.structName2structMembers(struct_name)) |mn| { // I do not return an error here because I should already check before is the struct exist
            if (std.mem.eql(u8, mn, member_name)) return true;
        }
        return false;
    }

    // Return true if the map have all the member name as key and not more
    pub fn checkIfAllMemberInMap(
        self: *FileEngine,
        struct_name: []const u8,
        map: *std.StringHashMap([]const u8),
        error_message_buffer: *std.ArrayList(u8),
    ) ZipponError!bool {
        const all_struct_member = try self.structName2structMembers(struct_name);
        var count: u16 = 0;

        const writer = error_message_buffer.writer();

        for (all_struct_member) |mn| {
            if (std.mem.eql(u8, mn, "id")) continue;
            if (map.contains(mn)) count += 1 else writer.print(" {s},", .{mn}) catch return FileEngineError.WriteError; // TODO: Handle missing print better
        }

        return ((count == all_struct_member.len - 1) and (count == map.count()));
    }
};
