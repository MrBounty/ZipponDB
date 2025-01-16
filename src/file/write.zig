const std = @import("std");
const config = @import("config");
const utils = @import("../utils.zig");
const zid = @import("ZipponData");
const Allocator = std.mem.Allocator;
const Self = @import("core.zig").Self;
const ZipponError = @import("error").ZipponError;

const SchemaStruct = @import("../schema/struct.zig");
const Filter = @import("../dataStructure/filter.zig").Filter;
const ConditionValue = @import("../dataStructure/filter.zig").ConditionValue;
const AdditionalData = @import("../dataStructure/additionalData.zig");
const RelationMap = @import("../dataStructure/relationMap.zig");
const JsonString = RelationMap.JsonString;
const EntityWriter = @import("entityWriter.zig");
const ThreadSyncContext = @import("../thread/context.zig");

const dtype = @import("dtype");
const s2t = dtype.s2t;
const UUID = dtype.UUID;
const DateTime = dtype.DateTime;
const DataType = dtype.DataType;
const log = std.log.scoped(.fileEngine);

var path_buffer: [1024]u8 = undefined;

pub fn addEntity(
    self: *Self,
    struct_name: []const u8,
    maps: []std.StringHashMap(ConditionValue),
    writer: anytype,
) ZipponError!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var file_index = try self.getFirstUsableIndexFile(struct_name);
    var path = std.fmt.bufPrint(&path_buffer, "{s}/DATA/{s}/{d}.zid", .{ self.path_to_ZipponDB_dir, struct_name, file_index }) catch return ZipponError.MemoryError;

    var data_writer = zid.DataWriter.init(path, null) catch return ZipponError.ZipponDataError;
    defer data_writer.deinit();

    const sstruct = try self.schema_engine.structName2SchemaStruct(struct_name);

    for (maps) |map| {
        const data = try self.orderedNewData(allocator, struct_name, map);
        data_writer.write(data) catch return ZipponError.ZipponDataError;
        sstruct.uuid_file_index.map.*.put(UUID{ .bytes = data[0].UUID }, file_index) catch return ZipponError.MemoryError;
        writer.print("\"{s}\", ", .{UUID.format_bytes(data[0].UUID)}) catch return ZipponError.WriteError;

        const file_stat = data_writer.fileStat() catch return ZipponError.ZipponDataError;
        if (file_stat.size > config.MAX_FILE_SIZE) {
            file_index = try self.getFirstUsableIndexFile(struct_name);
            data_writer.flush() catch return ZipponError.ZipponDataError;
            data_writer.deinit();

            path = std.fmt.bufPrint(&path_buffer, "{s}/DATA/{s}/{d}.zid", .{ self.path_to_ZipponDB_dir, struct_name, file_index }) catch return ZipponError.MemoryError;
            data_writer = zid.DataWriter.init(path, null) catch return ZipponError.ZipponDataError;
        }
    }

    data_writer.flush() catch return ZipponError.ZipponDataError;
}

pub fn updateEntities(
    self: *Self,
    struct_name: []const u8,
    filter: ?Filter,
    map: std.StringHashMap(ConditionValue),
    writer: anytype,
    additional_data: *AdditionalData,
) ZipponError!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const sstruct = try self.schema_engine.structName2SchemaStruct(struct_name);

    const dir = try self.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, sstruct.name }, .{});
    const to_parse = try self.allFileIndex(allocator, struct_name);

    // Multi-threading setup
    var sync_context = ThreadSyncContext.init(
        additional_data.limit,
        to_parse.len,
    );

    // Create a thread-safe writer for each file
    var thread_writer_list = allocator.alloc(std.ArrayList(u8), to_parse.len) catch return ZipponError.MemoryError;
    for (thread_writer_list) |*list| {
        list.* = std.ArrayList(u8).init(allocator);
    }

    var new_data_buff = allocator.alloc(zid.Data, sstruct.members.len) catch return ZipponError.MemoryError;

    // Convert the map to an array of ZipponData Data type, to be use with ZipponData writter
    for (sstruct.members, 0..) |member, i| {
        if (!map.contains(member)) continue;
        new_data_buff[i] = try @import("utils.zig").string2Data(allocator, map.get(member).?);
    }

    // Spawn threads for each file
    for (to_parse, 0..) |file_index, i| {
        self.thread_pool.spawn(updateEntitiesOneFile, .{
            new_data_buff,
            sstruct,
            filter,
            &map,
            thread_writer_list[i].writer(),
            file_index,
            dir,
            &sync_context,
        }) catch return ZipponError.ThreadError;
    }

    // Wait for all threads to complete
    while (!sync_context.isComplete()) std.time.sleep(100_000); // Check every 0.1ms

    // Combine results
    writer.writeByte('[') catch return ZipponError.WriteError;
    for (thread_writer_list) |list| {
        writer.writeAll(list.items) catch return ZipponError.WriteError;
    }
    writer.writeByte(']') catch return ZipponError.WriteError;
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
    var data_buffer: [config.BUFFER_SIZE]u8 = undefined;
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

    var finish_writing = false;
    while (iter.next() catch |err| {
        sync_context.logError("Parsing files", err);
        return;
    }) |row| {
        if (!finish_writing and (filter == null or filter.?.evaluate(row))) {
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

            writer.print("\"{s}\",", .{UUID.format_bytes(row[0].UUID)}) catch |err| {
                sync_context.logError("Error initializing DataWriter", err);
                zid.deleteFile(new_path, dir) catch {};
                return;
            };

            finish_writing = sync_context.incrementAndCheckStructLimit();
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

/// Delete all entity based on the filter. Will also write a JSON format list of all UUID deleted into the buffer
pub fn deleteEntities(
    self: *Self,
    struct_name: []const u8,
    filter: ?Filter,
    writer: anytype,
    additional_data: *AdditionalData,
) ZipponError!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const sstruct = try self.schema_engine.structName2SchemaStruct(struct_name);

    const dir = try self.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, sstruct.name }, .{});
    const to_parse = try self.allFileIndex(allocator, struct_name);

    // Multi-threading setup
    var sync_context = ThreadSyncContext.init(
        additional_data.limit,
        to_parse.len,
    );

    // Create a thread-safe writer for each file
    var thread_writer_list = allocator.alloc(std.ArrayList(u8), to_parse.len) catch return ZipponError.MemoryError;
    for (thread_writer_list) |*list| {
        list.* = std.ArrayList(u8).init(allocator);
    }

    // Spawn threads for each file
    for (to_parse, 0..) |file_index, i| {
        self.thread_pool.spawn(deleteEntitiesOneFile, .{
            sstruct,
            filter,
            thread_writer_list[i].writer(),
            file_index,
            dir,
            &sync_context,
        }) catch return ZipponError.ThreadError;
    }

    // Wait for all threads to complete
    while (!sync_context.isComplete()) std.time.sleep(100_000); // Check every 0.1ms

    // Combine results
    writer.writeByte('[') catch return ZipponError.WriteError;
    for (thread_writer_list) |list| {
        writer.writeAll(list.items) catch return ZipponError.WriteError;
    }
    writer.writeByte(']') catch return ZipponError.WriteError;

    //  FIXME: Stop doing that and just remove UUID from the map itself instead of reparsing everything at the end
    //  It's just that I can't do it in deleteEntitiesOneFile itself
    sstruct.uuid_file_index.map.clearRetainingCapacity();
    _ = sstruct.uuid_file_index.arena.reset(.free_all);
    try self.populateFileIndexUUIDMap(sstruct, sstruct.uuid_file_index);
}

fn deleteEntitiesOneFile(
    sstruct: SchemaStruct,
    filter: ?Filter,
    writer: anytype,
    file_index: u64,
    dir: std.fs.Dir,
    sync_context: *ThreadSyncContext,
) void {
    var data_buffer: [config.BUFFER_SIZE]u8 = undefined;
    var fa = std.heap.FixedBufferAllocator.init(&data_buffer);
    defer fa.reset();
    const allocator = fa.allocator();

    const path = std.fmt.allocPrint(allocator, "{d}.zid", .{file_index}) catch |err| {
        sync_context.logError("Error creating file path", err);
        return;
    };

    var iter = zid.DataIterator.init(allocator, path, dir, sstruct.zid_schema) catch |err| {
        sync_context.logError("Error initializing DataIterator", err);
        return;
    };
    defer iter.deinit();

    const new_path = std.fmt.allocPrint(allocator, "{d}.zid.new", .{file_index}) catch |err| {
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
    errdefer new_writer.deinit();

    var finish_writing = false;
    while (iter.next() catch |err| {
        sync_context.logError("Error during iter", err);
        return;
    }) |row| {
        if (!finish_writing and (filter == null or filter.?.evaluate(row))) {
            writer.print("{{\"{s}\"}},", .{UUID.format_bytes(row[0].UUID)}) catch |err| {
                sync_context.logError("Error writting", err);
                return;
            };

            finish_writing = sync_context.incrementAndCheckStructLimit();
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

    const file_stat = new_writer.fileStat() catch |err| {
        sync_context.logError("Error getting new file stat", err);
        return;
    };
    new_writer.deinit();
    if (file_index != 0 and file_stat.size == 0) dir.deleteFile(new_path) catch |err| {
        sync_context.logError("Error deleting empty new file", err);
        return;
    } else {
        dir.rename(new_path, path) catch |err| {
            sync_context.logError("Error renaming new file", err);
            return;
        };
    }

    sync_context.completeThread();
}
