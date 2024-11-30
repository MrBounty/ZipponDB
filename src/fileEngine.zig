const std = @import("std");
const utils = @import("stuffs/utils.zig");
const zid = @import("ZipponData");
const U64 = std.atomic.Value(u64);
const Pool = std.Thread.Pool;
const Allocator = std.mem.Allocator;
const SchemaEngine = @import("schemaEngine.zig").SchemaEngine;
const SchemaStruct = @import("schemaEngine.zig").SchemaStruct;
const ThreadSyncContext = @import("threadEngine.zig").ThreadSyncContext;
const EntityWriter = @import("entityWriter.zig").EntityWriter;

const dtype = @import("dtype");
const s2t = dtype.s2t;
const UUID = dtype.UUID;
const DateTime = dtype.DateTime;
const DataType = dtype.DataType;

const AdditionalData = @import("stuffs/additionalData.zig").AdditionalData;
const Filter = @import("stuffs/filter.zig").Filter;
const ConditionValue = @import("stuffs/filter.zig").ConditionValue;

const ZipponError = @import("stuffs/errors.zig").ZipponError;
const FileEngineError = @import("stuffs/errors.zig").FileEngineError;

const config = @import("config.zig");
const BUFFER_SIZE = config.BUFFER_SIZE;
const OUT_BUFFER_SIZE = config.OUT_BUFFER_SIZE;
const MAX_FILE_SIZE = config.MAX_FILE_SIZE;
const RESET_LOG_AT_RESTART = config.RESET_LOG_AT_RESTART;
const CPU_CORE = config.CPU_CORE;

const log = std.log.scoped(.fileEngine);

var parsing_buffer: [OUT_BUFFER_SIZE]u8 = undefined; // Maybe use an arena but this is faster
var path_buffer: [1024]u8 = undefined;
var path_to_ZipponDB_dir_buffer: [1024]u8 = undefined;

/// Manage everything that is relate to read or write in files
/// Or even get stats, whatever. If it touch files, it's here
pub const FileEngine = struct {
    path_to_ZipponDB_dir: []const u8,
    thread_pool: *Pool, // same pool as the ThreadEngine
    schema_engine: SchemaEngine = undefined, // This is init after the FileEngine and I attach after. Do I need to init after tho ?

    pub fn init(path: []const u8, thread_pool: *Pool) ZipponError!FileEngine {
        return FileEngine{
            .path_to_ZipponDB_dir = std.fmt.bufPrint(&path_to_ZipponDB_dir_buffer, "{s}", .{path}) catch return ZipponError.MemoryError,
            .thread_pool = thread_pool,
        };
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
        writer.print("Total size: {d:.2}Mb\n", .{@as(f64, @floatFromInt(main_size)) / 1024.0 / 1024.0}) catch return FileEngineError.WriteError;

        const log_dir = main_dir.openDir("LOG", .{ .iterate = true }) catch return FileEngineError.CantOpenDir;
        const log_size = utils.getDirTotalSize(log_dir) catch 0;
        writer.print("LOG: {d:.2}Mb\n", .{@as(f64, @floatFromInt(log_size)) / 1024.0 / 1024.0}) catch return FileEngineError.WriteError;

        const backup_dir = main_dir.openDir("BACKUP", .{ .iterate = true }) catch return FileEngineError.CantOpenDir;
        const backup_size = utils.getDirTotalSize(backup_dir) catch 0;
        writer.print("BACKUP: {d:.2}Mb\n", .{@as(f64, @floatFromInt(backup_size)) / 1024.0 / 1024.0}) catch return FileEngineError.WriteError;

        const data_dir = main_dir.openDir("DATA", .{ .iterate = true }) catch return FileEngineError.CantOpenDir;
        const data_size = utils.getDirTotalSize(data_dir) catch 0;
        writer.print("DATA: {d:.2}Mb\n", .{@as(f64, @floatFromInt(data_size)) / 1024.0 / 1024.0}) catch return FileEngineError.WriteError;

        var iter = data_dir.iterate();
        while (iter.next() catch return FileEngineError.DirIterError) |entry| {
            if (entry.kind != .directory) continue;
            const sub_dir = data_dir.openDir(entry.name, .{ .iterate = true }) catch return FileEngineError.CantOpenDir;
            const size = utils.getDirTotalSize(sub_dir) catch 0;
            writer.print("  {s}: {d:.}Mb {d} entities\n", .{
                entry.name,
                @as(f64, @floatFromInt(size)) / 1024.0 / 1024.0,
                try self.getNumberOfEntity(entry.name),
            }) catch return FileEngineError.WriteError;
        }
    }

    // --------------------Init folder and files--------------------

    /// Create the main folder. Including DATA, LOG and BACKUP
    /// TODO: Maybe start using a fixed lenght buffer instead of free everytime, but that not that important
    pub fn createMainDirectories(self: *FileEngine) ZipponError!void {
        var path_buff = std.fmt.bufPrint(&path_buffer, "{s}", .{self.path_to_ZipponDB_dir}) catch return FileEngineError.MemoryError;

        const cwd = std.fs.cwd();

        cwd.makeDir(path_buff) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return FileEngineError.CantMakeDir,
        };

        path_buff = std.fmt.bufPrint(&path_buffer, "{s}/DATA", .{self.path_to_ZipponDB_dir}) catch return FileEngineError.MemoryError;

        cwd.makeDir(path_buff) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return FileEngineError.CantMakeDir,
        };

        path_buff = std.fmt.bufPrint(&path_buffer, "{s}/BACKUP", .{self.path_to_ZipponDB_dir}) catch return FileEngineError.MemoryError;

        cwd.makeDir(path_buff) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return FileEngineError.CantMakeDir,
        };

        path_buff = std.fmt.bufPrint(&path_buffer, "{s}/LOG", .{self.path_to_ZipponDB_dir}) catch return FileEngineError.MemoryError;

        cwd.makeDir(path_buff) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return FileEngineError.CantMakeDir,
        };

        path_buff = std.fmt.bufPrint(&path_buffer, "{s}/LOG/log", .{self.path_to_ZipponDB_dir}) catch return FileEngineError.MemoryError;

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
        var fa = std.heap.FixedBufferAllocator.init(&parsing_buffer);
        fa.reset();
        const allocator = fa.allocator();

        const sstruct = try self.schema_engine.structName2SchemaStruct(struct_name);
        const max_file_index = try self.maxFileIndex(sstruct.name);
        var count: usize = 0;

        const dir = try utils.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, sstruct.name }, .{});

        for (0..(max_file_index + 1)) |i| {
            const path_buff = std.fmt.bufPrint(&path_buffer, "{d}.zid", .{i}) catch return FileEngineError.MemoryError;

            var iter = zid.DataIterator.init(allocator, path_buff, dir, sstruct.zid_schema) catch return FileEngineError.ZipponDataError;
            defer iter.deinit();

            while (iter.next() catch return FileEngineError.ZipponDataError) |_| count += 1;
        }

        return count;
    }

    const UUIDFileIndex = @import("stuffs/UUIDFileIndex.zig").UUIDIndexMap;

    /// Populate a map with all UUID bytes as key and file index as value
    /// This map is store in the SchemaStruct to then by using a list of UUID, get a list of file_index to parse
    pub fn populateFileIndexUUIDMap(
        self: *FileEngine,
        sstruct: SchemaStruct,
        map: *UUIDFileIndex,
    ) ZipponError!void {
        var fa = std.heap.FixedBufferAllocator.init(&parsing_buffer);
        fa.reset();
        const allocator = fa.allocator();

        const max_file_index = try self.maxFileIndex(sstruct.name);

        const dir = try utils.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, sstruct.name }, .{});

        // Multi-threading setup
        var sync_context = ThreadSyncContext.init(
            0,
            max_file_index + 1,
        );

        // Create a thread-safe writer for each file
        var thread_writer_list = allocator.alloc(std.ArrayList(UUID), max_file_index + 1) catch return FileEngineError.MemoryError;
        defer {
            for (thread_writer_list) |list| list.deinit();
            allocator.free(thread_writer_list);
        }

        for (thread_writer_list) |*list| {
            list.* = std.ArrayList(UUID).init(allocator);
        }

        // Spawn threads for each file
        for (0..(max_file_index + 1)) |file_index| {
            self.thread_pool.spawn(populateFileIndexUUIDMapOneFile, .{
                sstruct,
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
        for (thread_writer_list, 0..) |list, file_index| {
            for (list.items) |uuid| map.put(uuid, file_index) catch return ZipponError.MemoryError;
        }
    }

    fn populateFileIndexUUIDMapOneFile(
        sstruct: SchemaStruct,
        list: *std.ArrayList(UUID),
        file_index: u64,
        dir: std.fs.Dir,
        sync_context: *ThreadSyncContext,
    ) void {
        var data_buffer: [BUFFER_SIZE]u8 = undefined;
        var fa = std.heap.FixedBufferAllocator.init(&data_buffer);
        defer fa.reset();
        const allocator = fa.allocator();

        const path = std.fmt.bufPrint(&path_buffer, "{d}.zid", .{file_index}) catch |err| {
            sync_context.logError("Error creating file path", err);
            return;
        };

        var iter = zid.DataIterator.init(allocator, path, dir, sstruct.zid_schema) catch |err| {
            sync_context.logError("Error initializing DataIterator", err);
            return;
        };
        defer iter.deinit();

        while (iter.next() catch |err| {
            sync_context.logError("Error initializing DataIterator", err);
            return;
        }) |row| {
            list.*.append(UUID{ .bytes = row[0].UUID }) catch |err| {
                sync_context.logError("Error initializing DataIterator", err);
                return;
            };
        }

        _ = sync_context.completeThread();
    }

    /// Use a struct name and filter to populate a map with all UUID bytes as key and void as value
    /// This map is use as value for the ConditionValue of links, so I can do a `contains` on it.
    pub fn populateVoidUUIDMap(
        self: *FileEngine,
        struct_name: []const u8,
        filter: ?Filter,
        map: *std.AutoHashMap(UUID, void),
        additional_data: *AdditionalData,
    ) ZipponError!void {
        var fa = std.heap.FixedBufferAllocator.init(&parsing_buffer);
        fa.reset();
        const allocator = fa.allocator();

        const sstruct = try self.schema_engine.structName2SchemaStruct(struct_name);
        const max_file_index = try self.maxFileIndex(sstruct.name);

        const dir = try utils.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, sstruct.name }, .{});

        // Multi-threading setup
        var sync_context = ThreadSyncContext.init(
            additional_data.limit,
            max_file_index + 1,
        );

        // Create a thread-safe writer for each file
        var thread_writer_list = allocator.alloc(std.ArrayList(UUID), max_file_index + 1) catch return FileEngineError.MemoryError;

        for (thread_writer_list) |*list| {
            list.* = std.ArrayList(UUID).init(allocator);
        }

        // Spawn threads for each file
        for (0..(max_file_index + 1)) |file_index| {
            self.thread_pool.spawn(populateVoidUUIDMapOneFile, .{
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

        if (additional_data.limit == 0) return;

        if (map.count() > additional_data.limit) {
            log.err("Found {d} entity in populateVoidUUIDMap but max is: {d}", .{ map.count(), additional_data.limit });
            var iter = map.iterator();
            while (iter.next()) |entry| {
                log.debug("{s}", .{UUID.format_bytes(entry.key_ptr.bytes)});
            }
        }
    }

    fn populateVoidUUIDMapOneFile(
        sstruct: SchemaStruct,
        filter: ?Filter,
        list: *std.ArrayList(UUID),
        file_index: u64,
        dir: std.fs.Dir,
        sync_context: *ThreadSyncContext,
    ) void {
        var data_buffer: [BUFFER_SIZE]u8 = undefined;
        var fa = std.heap.FixedBufferAllocator.init(&data_buffer);
        defer fa.reset();
        const allocator = fa.allocator();

        const path = std.fmt.bufPrint(&path_buffer, "{d}.zid", .{file_index}) catch |err| {
            sync_context.logError("Error creating file path", err);
            return;
        };

        var iter = zid.DataIterator.init(allocator, path, dir, sstruct.zid_schema) catch |err| {
            sync_context.logError("Error initializing DataIterator", err);
            return;
        };
        defer iter.deinit();

        while (iter.next() catch |err| {
            sync_context.logError("Error in iter next", err);
            return;
        }) |row| {
            if (sync_context.checkStructLimit()) break;
            if (filter == null or filter.?.evaluate(row)) {
                list.*.append(UUID{ .bytes = row[0].UUID }) catch |err| {
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
    /// TODO: For relationship, if they are in additional_data and I need to return it with the other members, I will need to parse the file
    /// This is difficult, because that mean I need to parse file while parsing files ? I dont like that because it may be the same struct
    /// And because of multi thread, I can read the same file at the same time...
    pub fn parseEntities(
        self: *FileEngine,
        struct_name: []const u8,
        filter: ?Filter,
        additional_data: *AdditionalData,
        writer: anytype,
    ) ZipponError!void {
        var fa = std.heap.FixedBufferAllocator.init(&parsing_buffer);
        fa.reset();
        const allocator = fa.allocator();

        const sstruct = try self.schema_engine.structName2SchemaStruct(struct_name);
        const max_file_index = try self.maxFileIndex(sstruct.name);

        log.debug("Max file index {d}", .{max_file_index});

        // If there is no member to find, that mean we need to return all members, so let's populate additional data with all of them
        if (additional_data.childrens.items.len == 0) {
            additional_data.populateWithEverythingExceptLink(sstruct.members, sstruct.types) catch return FileEngineError.MemoryError;
        }

        // Open the dir that contain all files
        const dir = try utils.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, sstruct.name }, .{ .access_sub_paths = false });

        // Multi thread stuffs
        var sync_context = ThreadSyncContext.init(
            additional_data.limit,
            max_file_index + 1,
        );

        // Do one array and writer for each thread otherwise then create error by writing at the same time
        // Maybe use fixed lenght buffer for speed here
        var thread_writer_list = allocator.alloc(std.ArrayList(u8), max_file_index + 1) catch return FileEngineError.MemoryError;

        // Start parsing all file in multiple thread
        for (0..(max_file_index + 1)) |file_index| {
            thread_writer_list[file_index] = std.ArrayList(u8).init(allocator);

            self.thread_pool.spawn(parseEntitiesOneFile, .{
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
        //writer.writeByte('[') catch return FileEngineError.WriteError;
        for (thread_writer_list) |list| writer.writeAll(list.items) catch return FileEngineError.WriteError;
        //writer.writeByte(']') catch return FileEngineError.WriteError;
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
            if (sync_context.checkStructLimit()) break;
            if (filter) |f| if (!f.evaluate(row)) continue;

            EntityWriter.writeEntityJSON(
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

    // --------------------Change existing files--------------------

    // TODO: Make it in batch too
    pub fn addEntity(
        self: *FileEngine,
        struct_name: []const u8,
        map: std.StringHashMap(ConditionValue),
        writer: anytype,
        n: usize,
    ) ZipponError!void {
        var fa = std.heap.FixedBufferAllocator.init(&parsing_buffer);
        fa.reset();
        const allocator = fa.allocator();

        const file_index = try self.getFirstUsableIndexFile(struct_name);

        const path = std.fmt.bufPrint(&path_buffer, "{s}/DATA/{s}/{d}.zid", .{ self.path_to_ZipponDB_dir, struct_name, file_index }) catch return FileEngineError.MemoryError;
        const data = try self.orderedNewData(allocator, struct_name, map);

        std.debug.print("{any}", .{data});

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
        map: std.StringHashMap(ConditionValue),
        writer: anytype,
        additional_data: *AdditionalData,
    ) ZipponError!void {
        var fa = std.heap.FixedBufferAllocator.init(&parsing_buffer);
        fa.reset();
        const allocator = fa.allocator();

        const sstruct = try self.schema_engine.structName2SchemaStruct(struct_name);
        const max_file_index = try self.maxFileIndex(sstruct.name);

        const dir = try utils.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, sstruct.name }, .{});

        // Multi-threading setup
        var sync_context = ThreadSyncContext.init(
            additional_data.limit,
            max_file_index + 1,
        );

        // Create a thread-safe writer for each file
        var thread_writer_list = allocator.alloc(std.ArrayList(u8), max_file_index + 1) catch return FileEngineError.MemoryError;
        for (thread_writer_list) |*list| {
            list.* = std.ArrayList(u8).init(allocator);
        }

        var new_data_buff = allocator.alloc(zid.Data, sstruct.members.len) catch return ZipponError.MemoryError;

        // Convert the map to an array of ZipponData Data type, to be use with ZipponData writter
        for (sstruct.members, 0..) |member, i| {
            if (!map.contains(member)) continue;
            new_data_buff[i] = try string2Data(allocator, map.get(member).?);
        }

        // Spawn threads for each file
        for (0..(max_file_index + 1)) |file_index| {
            self.thread_pool.spawn(updateEntitiesOneFile, .{
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
        map: *const std.StringHashMap(ConditionValue),
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
            if (sync_context.checkStructLimit()) break;
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
        var fa = std.heap.FixedBufferAllocator.init(&parsing_buffer);
        fa.reset();
        const allocator = fa.allocator();

        const sstruct = try self.schema_engine.structName2SchemaStruct(struct_name);
        const max_file_index = try self.maxFileIndex(sstruct.name);

        const dir = try utils.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, sstruct.name }, .{});

        // Multi-threading setup
        var sync_context = ThreadSyncContext.init(
            additional_data.limit,
            max_file_index + 1,
        );

        // Create a thread-safe writer for each file
        var thread_writer_list = allocator.alloc(std.ArrayList(u8), max_file_index + 1) catch return FileEngineError.MemoryError;
        for (thread_writer_list) |*list| {
            list.* = std.ArrayList(u8).init(allocator);
        }

        // Spawn threads for each file
        for (0..(max_file_index + 1)) |file_index| {
            self.thread_pool.spawn(deleteEntitiesOneFile, .{
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
            if (sync_context.checkStructLimit()) break;
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

    //TODO: Update to make it use ConditionValue
    fn string2Data(allocator: Allocator, value: ConditionValue) ZipponError!zid.Data {
        switch (value) {
            .int => |v| return zid.Data.initInt(v),
            .float => |v| return zid.Data.initFloat(v),
            .bool_ => |v| return zid.Data.initBool(v),
            .unix => |v| return zid.Data.initUnix(v),
            .str => |v| return zid.Data.initStr(v),
            .link => |v| {
                var iter = v.keyIterator();
                if (v.count() > 0) {
                    return zid.Data.initUUID(iter.next().?.bytes);
                } else {
                    const uuid = UUID.parse("00000000-0000-0000-0000-000000000000") catch return ZipponError.InvalidUUID;
                    return zid.Data.initUUID(uuid.bytes);
                }
            },
            .link_array => |v| {
                var iter = v.keyIterator();
                var items = std.ArrayList([16]u8).init(allocator);
                defer items.deinit();

                while (iter.next()) |uuid| {
                    items.append(uuid.bytes) catch return ZipponError.MemoryError;
                }
                return zid.Data.initUUIDArray(zid.allocEncodArray.UUID(allocator, items.items) catch return FileEngineError.AllocEncodError);
            },
            .self => |v| return zid.Data.initUUID(v.bytes),
            .int_array => |v| return zid.Data.initIntArray(zid.allocEncodArray.Int(allocator, v) catch return FileEngineError.AllocEncodError),
            .float_array => |v| return zid.Data.initFloatArray(zid.allocEncodArray.Float(allocator, v) catch return FileEngineError.AllocEncodError),
            .str_array => |v| return zid.Data.initStrArray(zid.allocEncodArray.Str(allocator, v) catch return FileEngineError.AllocEncodError),
            .bool_array => |v| return zid.Data.initBoolArray(zid.allocEncodArray.Bool(allocator, v) catch return FileEngineError.AllocEncodError),
            .unix_array => |v| return zid.Data.initUnixArray(zid.allocEncodArray.Unix(allocator, v) catch return FileEngineError.AllocEncodError),
        }
    }

    /// Take a map from the parseNewData and return an ordered array of Data to be use in a DataWriter
    /// TODO: Optimize
    fn orderedNewData(
        self: *FileEngine,
        allocator: Allocator,
        struct_name: []const u8,
        map: std.StringHashMap(ConditionValue),
    ) ZipponError![]zid.Data {
        const members = try self.schema_engine.structName2structMembers(struct_name);
        var datas = allocator.alloc(zid.Data, (members.len)) catch return FileEngineError.MemoryError;

        const new_uuid = UUID.init();
        datas[0] = zid.Data.initUUID(new_uuid.bytes);

        for (members, 0..) |member, i| {
            if (i == 0) continue; // Skip the id
            datas[i] = try string2Data(allocator, map.get(member).?);
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
                log.debug("{s}\n\n", .{entry.name});
                return std.fmt.parseInt(usize, entry.name[0..(entry.name.len - 4)], 10) catch return FileEngineError.InvalidFileIndex; // INFO: Hardcoded len of file extension
            }
        }

        const path = std.fmt.bufPrint(&path_buffer, "{s}/DATA/{s}/{d}.zid", .{ self.path_to_ZipponDB_dir, struct_name, i }) catch return FileEngineError.MemoryError;
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
