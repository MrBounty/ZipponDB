const std = @import("std");
const utils = @import("stuffs/utils.zig");
const zid = @import("ZipponData");
const U64 = std.atomic.Value(u64);
const Pool = std.Thread.Pool;
const Allocator = std.mem.Allocator;
const SchemaEngine = @import("schemaEngine.zig").SchemaEngine;
const SchemaStruct = @import("schemaParser.zig").Parser.SchemaStruct;

const dtype = @import("dtype");
const s2t = dtype.s2t;
const UUID = dtype.UUID;
const DateTime = dtype.DateTime;
const DataType = dtype.DataType;

const AdditionalData = @import("stuffs/additionalData.zig").AdditionalData;
const Filter = @import("stuffs/filter.zig").Filter;

const ZipponError = @import("stuffs/errors.zig").ZipponError;
const FileEngineError = @import("stuffs/errors.zig").FileEngineError;

const config = @import("config.zig");
const BUFFER_SIZE = config.BUFFER_SIZE;
const MAX_FILE_SIZE = config.MAX_FILE_SIZE;
const RESET_LOG_AT_RESTART = config.RESET_LOG_AT_RESTART;
const CPU_CORE = config.CPU_CORE;

const log = std.log.scoped(.fileEngine);

// TODO: Start using State at the start and end of each function for debugging
const FileEngineState = enum { Parsing, Waiting };

const ThreadSyncContext = struct {
    processed_struct: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    error_file: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    completed_file: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    max_struct: u64,
    max_file: u64,

    fn init(max_struct: u64, max_file: u64) ThreadSyncContext {
        return ThreadSyncContext{
            .max_struct = max_struct,
            .max_file = max_file,
        };
    }

    fn isComplete(self: *ThreadSyncContext) bool {
        return (self.completed_file.load(.acquire) + self.error_file.load(.acquire)) >= self.max_file;
    }

    fn completeThread(self: *ThreadSyncContext) void {
        _ = self.completed_file.fetchAdd(1, .release);
    }

    fn incrementAndCheckStructLimit(self: *ThreadSyncContext) bool {
        if (self.max_struct == 0) return false;
        const new_count = self.processed_struct.fetchAdd(1, .monotonic);
        return new_count >= self.max_struct;
    }

    fn logError(self: *ThreadSyncContext, message: []const u8, err: anyerror) void {
        log.err("{s}: {any}", .{ message, err });
        _ = self.error_file.fetchAdd(1, .acquire);
    }
};

/// Manage everything that is relate to read or write in files
/// Or even get stats, whatever. If it touch files, it's here
pub const FileEngine = struct {
    allocator: Allocator,
    state: FileEngineState,
    path_to_ZipponDB_dir: []const u8,
    schema_engine: SchemaEngine = undefined, // I dont really like that here

    pub fn init(allocator: Allocator, path: []const u8) ZipponError!FileEngine {
        return FileEngine{
            .allocator = allocator,
            .path_to_ZipponDB_dir = allocator.dupe(u8, path) catch return ZipponError.MemoryError,
            .state = .Waiting,
        };
    }

    pub fn deinit(self: *FileEngine) void {
        self.allocator.free(self.path_to_ZipponDB_dir);
    }

    pub fn usable(self: FileEngine) bool {
        return self.state == .Waiting;
    }

    // --------------------Other--------------------

    pub fn readSchemaFile(sub_path: []const u8, buffer: []u8) ZipponError!usize {
        const file = std.fs.cwd().openFile(sub_path, .{}) catch return ZipponError.CantOpenFile;
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
    /// TODO: Maybe start using a fixed lenght buffer instead of free everytime, but that not that important
    pub fn createMainDirectories(self: *FileEngine) ZipponError!void {
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
            _ = std.fs.cwd().openFile(path_buff, .{}) catch {
                _ = cwd.createFile(path_buff, .{}) catch return FileEngineError.CantMakeFile;
            };
        }
    }

    /// Request a path to a schema file and then create the struct folder
    /// TODO: Check if some data already exist and if so ask if the user want to delete it and make a backup
    pub fn createStructDirectories(self: *FileEngine, struct_array: []SchemaStruct) ZipponError!void {
        var data_dir = try utils.printOpenDir("{s}/DATA", .{self.path_to_ZipponDB_dir}, .{});
        defer data_dir.close();

        for (struct_array) |schema_struct| {
            data_dir.makeDir(schema_struct.name) catch |err| switch (err) {
                error.PathAlreadyExists => continue,
                else => return FileEngineError.CantMakeDir,
            };
            const struct_dir = data_dir.openDir(schema_struct.name, .{}) catch return FileEngineError.CantOpenDir;

            zid.createFile("0.zid", struct_dir) catch return FileEngineError.CantMakeFile;
        }
    }

    // --------------------Read and parse files--------------------

    /// Use a struct name to populate a list with all UUID of this struct
    /// TODO: Multi thread that too
    pub fn getNumberOfEntity(self: *FileEngine, struct_name: []const u8) ZipponError!usize {
        const sstruct = try self.schema_engine.structName2SchemaStruct(struct_name);
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

    /// Use a struct name and filter to populate a map with all UUID bytes as key and void as value
    pub fn populateUUIDMap(
        self: *FileEngine,
        struct_name: []const u8,
        filter: ?Filter,
        map: *std.AutoHashMap([16]u8, void),
        additional_data: *AdditionalData,
    ) ZipponError!void {
        const sstruct = try self.schema_engine.structName2SchemaStruct(struct_name);
        const max_file_index = try self.maxFileIndex(sstruct.name);

        const dir = try utils.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, sstruct.name }, .{});

        // Multi-threading setup
        var arena = std.heap.ThreadSafeAllocator{
            .child_allocator = self.allocator,
        };

        var pool: std.Thread.Pool = undefined;
        defer pool.deinit();
        pool.init(std.Thread.Pool.Options{
            .allocator = arena.allocator(),
            .n_jobs = CPU_CORE,
        }) catch return ZipponError.ThreadError;

        var sync_context = ThreadSyncContext.init(
            additional_data.entity_count_to_find,
            max_file_index + 1,
        );

        // Create a thread-safe writer for each file
        var thread_writer_list = self.allocator.alloc(std.ArrayList([16]u8), max_file_index + 1) catch return FileEngineError.MemoryError;
        defer {
            for (thread_writer_list) |list| list.deinit();
            self.allocator.free(thread_writer_list);
        }

        for (thread_writer_list) |*list| {
            list.* = std.ArrayList([16]u8).init(self.allocator);
        }

        // Spawn threads for each file
        for (0..(max_file_index + 1)) |file_index| {
            pool.spawn(populateUUIDMapOneFile, .{
                sstruct,
                filter,
                &thread_writer_list[file_index],
                file_index,
                dir,
                &sync_context,
            }) catch return FileEngineError.ThreadError;
        }

        // Wait for all threads to complete
        while (!sync_context.isComplete()) {
            std.time.sleep(10_000_000);
        }

        // Combine results
        for (thread_writer_list) |list| {
            for (list.items) |uuid| _ = map.getOrPut(uuid) catch return ZipponError.MemoryError;
        }
    }

    fn populateUUIDMapOneFile(
        sstruct: SchemaStruct,
        filter: ?Filter,
        list: *std.ArrayList([16]u8),
        file_index: u64,
        dir: std.fs.Dir,
        sync_context: *ThreadSyncContext,
    ) void {
        var data_buffer: [BUFFER_SIZE]u8 = undefined;
        var fa = std.heap.FixedBufferAllocator.init(&data_buffer);
        defer fa.reset();
        const allocator = fa.allocator();

        var path_buffer: [128]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buffer, "{d}.zid", .{file_index}) catch |err| {
            sync_context.logError("Error creating file path", err);
            return;
        };

        var iter = zid.DataIterator.init(allocator, path, dir, sstruct.zid_schema) catch |err| {
            sync_context.logError("Error initializing DataIterator", err);
            return;
        };
        defer iter.deinit();

        while (iter.next() catch return) |row| {
            if (filter == null or filter.?.evaluate(row)) {
                list.*.append(row[0].UUID) catch |err| {
                    sync_context.logError("Error initializing DataIterator", err);
                    return;
                };

                if (sync_context.incrementAndCheckStructLimit()) break;
            }
        }

        _ = sync_context.completeThread();
    }

    /// Take a filter, parse all file and if one struct if validate by the filter, write it in a JSON format to the writer
    /// filter can be null. This will return all of them
    pub fn parseEntities(
        self: *FileEngine,
        struct_name: []const u8,
        filter: ?Filter,
        additional_data: *AdditionalData,
        writer: anytype,
    ) ZipponError!void {
        const sstruct = try self.schema_engine.structName2SchemaStruct(struct_name);
        const max_file_index = try self.maxFileIndex(sstruct.name);

        log.debug("Max file index {d}", .{max_file_index});

        // If there is no member to find, that mean we need to return all members, so let's populate additional data with all of them
        if (additional_data.member_to_find.items.len == 0) {
            additional_data.populateWithEverything(self.allocator, sstruct.members) catch return FileEngineError.MemoryError;
        }

        // Open the dir that contain all files
        const dir = try utils.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, sstruct.name }, .{ .access_sub_paths = false });

        // Multi thread stuffs
        var arena = std.heap.ThreadSafeAllocator{
            .child_allocator = self.allocator,
        };

        var pool: std.Thread.Pool = undefined;
        defer pool.deinit();
        pool.init(std.Thread.Pool.Options{
            .allocator = arena.allocator(),
            .n_jobs = CPU_CORE,
        }) catch return ZipponError.ThreadError;

        var sync_context = ThreadSyncContext.init(
            additional_data.entity_count_to_find,
            max_file_index + 1,
        );

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

            pool.spawn(parseEntitiesOneFile, .{
                thread_writer_list[file_index].writer(),
                file_index,
                dir,
                sstruct.zid_schema,
                filter,
                additional_data,
                try self.schema_engine.structName2DataType(struct_name),
                &sync_context,
            }) catch return FileEngineError.ThreadError;
        }

        // Wait for all thread to either finish or return an error
        while (!sync_context.isComplete()) {
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
        sync_context: *ThreadSyncContext,
    ) void {
        log.debug("{any}\n", .{@TypeOf(writer)});
        var data_buffer: [BUFFER_SIZE]u8 = undefined;
        var fa = std.heap.FixedBufferAllocator.init(&data_buffer);
        defer fa.reset();
        const allocator = fa.allocator();

        var path_buffer: [16]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buffer, "{d}.zid", .{file_index}) catch |err| {
            sync_context.logError("Error creating file path", err);
            return;
        };

        var iter = zid.DataIterator.init(allocator, path, dir, zid_schema) catch |err| {
            sync_context.logError("Error initializing DataIterator", err);
            return;
        };

        while (iter.next() catch |err| {
            sync_context.logError("Error in iter next", err);
            return;
        }) |row| {
            if (filter) |f| if (!f.evaluate(row)) continue;

            writeEntity(
                writer,
                row,
                additional_data,
                data_types,
            ) catch |err| {
                sync_context.logError("Error writing entity", err);
                return;
            };
            if (sync_context.incrementAndCheckStructLimit()) break;
        }

        _ = sync_context.completeThread();
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
            .Unix => |v| {
                const datetime = DateTime.initUnix(v);
                try writer.writeByte('"');
                switch (data_type) {
                    .date => try datetime.format("YYYY/MM/DD", writer),
                    .time => try datetime.format("HH:mm:ss.SSSS", writer),
                    .datetime => try datetime.format("YYYY/MM/DD-HH:mm:ss.SSSS", writer),
                    else => unreachable,
                }
                try writer.writeByte('"');
            },
            .IntArray, .FloatArray, .StrArray, .UUIDArray, .BoolArray, .UnixArray => try writeArray(writer, value, data_type),
        }
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
        const sstruct = try self.schema_engine.structName2SchemaStruct(struct_name);
        const max_file_index = try self.maxFileIndex(sstruct.name);

        const dir = try utils.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, sstruct.name }, .{});

        // Multi-threading setup
        var arena = std.heap.ThreadSafeAllocator{
            .child_allocator = self.allocator,
        };

        var pool: std.Thread.Pool = undefined;
        defer pool.deinit();
        pool.init(std.Thread.Pool.Options{
            .allocator = arena.allocator(),
            .n_jobs = CPU_CORE,
        }) catch return ZipponError.ThreadError;

        var sync_context = ThreadSyncContext.init(
            additional_data.entity_count_to_find,
            max_file_index + 1,
        );

        // Create a thread-safe writer for each file
        var thread_writer_list = self.allocator.alloc(std.ArrayList(u8), max_file_index + 1) catch return FileEngineError.MemoryError;
        defer {
            for (thread_writer_list) |list| list.deinit();
            self.allocator.free(thread_writer_list);
        }

        for (thread_writer_list) |*list| {
            list.* = std.ArrayList(u8).init(self.allocator);
        }

        var data_buffer: [BUFFER_SIZE]u8 = undefined;
        var fa = std.heap.FixedBufferAllocator.init(&data_buffer);
        defer fa.reset();
        const data_allocator = fa.allocator();

        var new_data_buff = data_allocator.alloc(zid.Data, sstruct.members.len) catch return ZipponError.MemoryError;

        // Convert the map to an array of ZipponData Data type, to be use with ZipponData writter
        for (sstruct.members, 0..) |member, i| {
            if (!map.contains(member)) continue;

            const dt = try self.schema_engine.memberName2DataType(struct_name, member);
            new_data_buff[i] = try string2Data(data_allocator, dt, map.get(member).?);
        }

        // Spawn threads for each file
        for (0..(max_file_index + 1)) |file_index| {
            pool.spawn(updateEntitiesOneFile, .{
                new_data_buff,
                sstruct,
                filter,
                &map,
                thread_writer_list[file_index].writer(),
                file_index,
                dir,
                &sync_context,
            }) catch return FileEngineError.ThreadError;
        }

        // Wait for all threads to complete
        while (!sync_context.isComplete()) {
            std.time.sleep(10_000_000); // Check every 10ms
        }

        // Combine results
        writer.writeByte('[') catch return FileEngineError.WriteError;
        for (thread_writer_list) |list| {
            writer.writeAll(list.items) catch return FileEngineError.WriteError;
        }
        writer.writeByte(']') catch return FileEngineError.WriteError;
    }

    fn updateEntitiesOneFile(
        new_data_buff: []zid.Data,
        sstruct: SchemaStruct,
        filter: ?Filter,
        map: *const std.StringHashMap([]const u8),
        writer: anytype,
        file_index: u64,
        dir: std.fs.Dir,
        sync_context: *ThreadSyncContext,
    ) void {
        log.debug("{any}\n", .{@TypeOf(writer)});
        var data_buffer: [BUFFER_SIZE]u8 = undefined;
        var fa = std.heap.FixedBufferAllocator.init(&data_buffer);
        defer fa.reset();
        const allocator = fa.allocator();

        var path_buffer: [128]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buffer, "{d}.zid", .{file_index}) catch |err| {
            sync_context.logError("Error creating file path", err);
            return;
        };

        var iter = zid.DataIterator.init(allocator, path, dir, sstruct.zid_schema) catch |err| {
            sync_context.logError("Error initializing DataIterator", err);
            return;
        };
        defer iter.deinit();

        const new_path = std.fmt.allocPrint(allocator, "{d}.zid.new", .{file_index}) catch |err| {
            sync_context.logError("Error creating new file path", err);
            return;
        };
        defer allocator.free(new_path);

        zid.createFile(new_path, dir) catch |err| {
            sync_context.logError("Error creating new file", err);
            return;
        };

        var new_writer = zid.DataWriter.init(new_path, dir) catch |err| {
            sync_context.logError("Error initializing DataWriter", err);
            zid.deleteFile(new_path, dir) catch {};
            return;
        };
        defer new_writer.deinit();

        while (iter.next() catch |err| {
            sync_context.logError("Parsing files", err);
            return;
        }) |row| {
            if (filter == null or filter.?.evaluate(row)) {
                // Add the unchanged Data in the new_data_buff
                new_data_buff[0] = row[0];
                for (sstruct.members, 0..) |member, i| {
                    if (map.contains(member)) continue;
                    new_data_buff[i] = row[i];
                }

                log.debug("{d} {any}\n\n", .{ new_data_buff.len, new_data_buff });

                new_writer.write(new_data_buff) catch |err| {
                    sync_context.logError("Error initializing DataWriter", err);
                    zid.deleteFile(new_path, dir) catch {};
                    return;
                };

                writer.print("{{\"{s}\"}},", .{UUID.format_bytes(row[0].UUID)}) catch |err| {
                    sync_context.logError("Error initializing DataWriter", err);
                    zid.deleteFile(new_path, dir) catch {};
                    return;
                };

                if (sync_context.incrementAndCheckStructLimit()) break;
            } else {
                new_writer.write(row) catch |err| {
                    sync_context.logError("Error initializing DataWriter", err);
                    zid.deleteFile(new_path, dir) catch {};
                    return;
                };
            }
        }

        new_writer.flush() catch |err| {
            sync_context.logError("Error initializing DataWriter", err);
            zid.deleteFile(new_path, dir) catch {};
            return;
        };

        dir.deleteFile(path) catch |err| {
            sync_context.logError("Error deleting old file", err);
            return;
        };

        dir.rename(new_path, path) catch |err| {
            sync_context.logError("Error initializing DataWriter", err);
            return;
        };

        _ = sync_context.completeThread();
    }

    /// Will delete all entity based on the filter. Will also write a JSON format list of all UUID deleted into the buffer
    pub fn deleteEntities(
        self: *FileEngine,
        struct_name: []const u8,
        filter: ?Filter,
        writer: anytype,
        additional_data: *AdditionalData,
    ) ZipponError!void {
        const sstruct = try self.schema_engine.structName2SchemaStruct(struct_name);
        const max_file_index = try self.maxFileIndex(sstruct.name);

        const dir = try utils.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, sstruct.name }, .{});

        // Multi-threading setup
        var arena = std.heap.ThreadSafeAllocator{
            .child_allocator = self.allocator,
        };

        var pool: std.Thread.Pool = undefined;
        defer pool.deinit();
        pool.init(std.Thread.Pool.Options{
            .allocator = arena.allocator(),
            .n_jobs = CPU_CORE,
        }) catch return ZipponError.ThreadError;

        var sync_context = ThreadSyncContext.init(
            additional_data.entity_count_to_find,
            max_file_index + 1,
        );

        // Create a thread-safe writer for each file
        var thread_writer_list = self.allocator.alloc(std.ArrayList(u8), max_file_index + 1) catch return FileEngineError.MemoryError;
        defer {
            for (thread_writer_list) |list| list.deinit();
            self.allocator.free(thread_writer_list);
        }

        for (thread_writer_list) |*list| {
            list.* = std.ArrayList(u8).init(self.allocator);
        }

        // Spawn threads for each file
        for (0..(max_file_index + 1)) |file_index| {
            pool.spawn(deleteEntitiesOneFile, .{
                sstruct,
                filter,
                thread_writer_list[file_index].writer(),
                file_index,
                dir,
                &sync_context,
            }) catch return FileEngineError.ThreadError;
        }

        // Wait for all threads to complete
        while (!sync_context.isComplete()) {
            std.time.sleep(10_000_000); // Check every 10ms
        }

        // Combine results
        // TODO: Make a struct for writing
        writer.writeByte('[') catch return FileEngineError.WriteError;
        for (thread_writer_list) |list| {
            writer.writeAll(list.items) catch return FileEngineError.WriteError;
        }
        writer.writeByte(']') catch return FileEngineError.WriteError;
    }

    fn deleteEntitiesOneFile(
        sstruct: SchemaStruct,
        filter: ?Filter,
        writer: anytype,
        file_index: u64,
        dir: std.fs.Dir,
        sync_context: *ThreadSyncContext,
    ) void {
        var data_buffer: [BUFFER_SIZE]u8 = undefined;
        var fa = std.heap.FixedBufferAllocator.init(&data_buffer);
        defer fa.reset();
        const allocator = fa.allocator();

        var path_buffer: [128]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buffer, "{d}.zid", .{file_index}) catch |err| {
            sync_context.logError("Error creating file path", err);
            return;
        };

        var iter = zid.DataIterator.init(allocator, path, dir, sstruct.zid_schema) catch |err| {
            sync_context.logError("Error initializing DataIterator", err);
            return;
        };
        defer iter.deinit();

        var new_path_buffer: [128]u8 = undefined;
        const new_path = std.fmt.bufPrint(&new_path_buffer, "{d}.zid.new", .{file_index}) catch |err| {
            sync_context.logError("Error creating file path", err);
            return;
        };

        zid.createFile(new_path, dir) catch |err| {
            sync_context.logError("Error creating new file", err);
            return;
        };

        var new_writer = zid.DataWriter.init(new_path, dir) catch |err| {
            sync_context.logError("Error initializing DataWriter", err);
            return;
        };
        defer new_writer.deinit();

        while (iter.next() catch |err| {
            sync_context.logError("Error during iter", err);
            return;
        }) |row| {
            if (filter == null or filter.?.evaluate(row)) {
                writer.print("{{\"{s}\"}},", .{UUID.format_bytes(row[0].UUID)}) catch |err| {
                    sync_context.logError("Error writting", err);
                    return;
                };

                if (sync_context.incrementAndCheckStructLimit()) break;
            } else {
                new_writer.write(row) catch |err| {
                    sync_context.logError("Error writing unchanged data", err);
                    return;
                };
            }
        }

        new_writer.flush() catch |err| {
            sync_context.logError("Error flushing new writer", err);
            return;
        };

        dir.deleteFile(path) catch |err| {
            sync_context.logError("Error deleting old file", err);
            return;
        };

        dir.rename(new_path, path) catch |err| {
            sync_context.logError("Error renaming new file", err);
            return;
        };

        _ = sync_context.completeThread();
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
                return zid.Data.initUUID(uuid.bytes);
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

                return zid.Data.initBoolArray(zid.allocEncodArray.Bool(allocator, array) catch return FileEngineError.AllocEncodError);
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
            .link_array => {
                const array = s2t.parseArrayUUIDBytes(allocator, value) catch return FileEngineError.MemoryError;
                defer allocator.free(array);

                return zid.Data.initUUIDArray(zid.allocEncodArray.UUID(allocator, array) catch return FileEngineError.AllocEncodError);
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
        const members = try self.schema_engine.structName2structMembers(struct_name);
        const types = try self.schema_engine.structName2DataType(struct_name);

        var datas = allocator.alloc(zid.Data, (members.len)) catch return FileEngineError.MemoryError;

        const new_uuid = UUID.init();
        datas[0] = zid.Data.initUUID(new_uuid.bytes);

        for (members, types, 0..) |member, dt, i| {
            if (i == 0) continue; // Skip the id
            datas[i] = try string2Data(allocator, dt, map.get(member).?);
        }

        log.debug("New ordered data: {any}\n", .{datas});

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
                log.debug("{s}\n\n", .{entry.name});
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
        _ = utils.printOpenFile("{s}/schema", .{self.path_to_ZipponDB_dir}, .{}) catch return false;
        return true;
    }

    pub fn writeSchemaFile(self: *FileEngine, null_terminated_schema_buff: [:0]const u8) FileEngineError!void {
        var zippon_dir = std.fs.cwd().openDir(self.path_to_ZipponDB_dir, .{}) catch return FileEngineError.MemoryError;
        defer zippon_dir.close();

        zippon_dir.deleteFile("schema") catch |err| switch (err) {
            error.FileNotFound => {},
            else => return FileEngineError.DeleteFileError,
        };

        var file = zippon_dir.createFile("schema", .{}) catch return FileEngineError.CantMakeFile;
        defer file.close();
        file.writeAll(null_terminated_schema_buff) catch return FileEngineError.WriteError;
    }
};
