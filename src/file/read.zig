const std = @import("std");
const config = @import("config");
const utils = @import("../utils.zig");
const zid = @import("ZipponData");
const Allocator = std.mem.Allocator;
const ZipponError = @import("error").ZipponError;

const SchemaStruct = @import("../schema/struct.zig");
const Filter = @import("../dataStructure/filter.zig").Filter;
const AdditionalData = @import("../dataStructure/additionalData.zig");
const RelationMap = @import("../dataStructure/relationMap.zig");
const UUIDFileIndex = @import("../dataStructure/UUIDFileIndex.zig").UUIDIndexMap;
const JsonString = @import("../dataStructure/relationMap.zig").JsonString;
const EntityWriter = @import("entityWriter.zig");
const ThreadSyncContext = @import("../thread/context.zig");

const dtype = @import("dtype");
const s2t = dtype.s2t;
const UUID = dtype.UUID;
const DateTime = dtype.DateTime;
const DataType = dtype.DataType;
const log = std.log.scoped(.fileEngine);

const Self = @import("core.zig").Self;

var path_buffer: [1024]u8 = undefined;

/// Use a struct name to populate a list with all UUID of this struct
/// TODO: Multi thread that too
pub fn getNumberOfEntityAndFile(self: *Self, struct_name: []const u8) ZipponError!struct { entity: usize, file: usize } {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const sstruct = try self.schema_engine.structName2SchemaStruct(struct_name);
    const to_parse = try self.allFileIndex(allocator, struct_name);
    defer allocator.free(to_parse);

    return .{ .entity = sstruct.uuid_file_index.map.count(), .file = to_parse.len };
}

/// Populate a map with all UUID bytes as key and file index as value
/// This map is store in the SchemaStruct to then by using a list of UUID, get a list of file_index to parse
pub fn populateFileIndexUUIDMap(
    self: *Self,
    sstruct: SchemaStruct,
    map: *UUIDFileIndex,
) ZipponError!void {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const dir = try self.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, sstruct.name }, .{});
    const to_parse = try self.allFileIndex(allocator, sstruct.name);

    // Multi-threading setup
    var sync_context = ThreadSyncContext.init(
        0,
        to_parse.len,
    );

    // Create a thread-safe writer for each file
    var thread_writer_list = allocator.alloc(std.ArrayList(UUID), to_parse.len) catch return ZipponError.MemoryError;
    defer {
        for (thread_writer_list) |list| list.deinit();
        allocator.free(thread_writer_list);
    }

    for (thread_writer_list) |*list| {
        list.* = std.ArrayList(UUID).init(allocator);
    }

    // Spawn threads for each file
    for (to_parse, 0..) |file_index, i| {
        self.thread_pool.spawn(populateFileIndexUUIDMapOneFile, .{
            sstruct,
            &thread_writer_list[i],
            file_index,
            dir,
            &sync_context,
        }) catch return ZipponError.ThreadError;
    }

    // Wait for all threads to complete
    while (!sync_context.isComplete()) std.time.sleep(10_000_000);

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
    self: *Self,
    struct_name: []const u8,
    filter: ?Filter,
    map: *std.AutoHashMap(UUID, void),
    additional_data: *AdditionalData,
) ZipponError!void {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const sstruct = try self.schema_engine.structName2SchemaStruct(struct_name);

    const dir = try self.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, sstruct.name }, .{});
    const to_parse = try self.allFileIndex(allocator, sstruct.name);

    // Multi-threading setup
    var sync_context = ThreadSyncContext.init(
        additional_data.limit,
        to_parse.len,
    );

    // Create a thread-safe writer for each file
    var thread_writer_list = allocator.alloc(std.ArrayList(UUID), to_parse.len + 1) catch return ZipponError.MemoryError;

    for (thread_writer_list) |*list| {
        list.* = std.ArrayList(UUID).init(allocator);
    }

    // Spawn threads for each file
    for (to_parse, 0..) |file_index, i| {
        self.thread_pool.spawn(populateVoidUUIDMapOneFile, .{
            sstruct,
            filter,
            &thread_writer_list[i],
            file_index,
            dir,
            &sync_context,
        }) catch return ZipponError.ThreadError;
    }

    // Wait for all threads to complete
    while (!sync_context.isComplete()) std.time.sleep(10_000_000);

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
pub fn parseEntities(
    self: *Self,
    struct_name: []const u8,
    filter: ?Filter,
    additional_data: *AdditionalData,
    entry_allocator: Allocator,
) ZipponError![]const u8 {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var buff = std.ArrayList(u8).init(entry_allocator);
    defer buff.deinit();
    const writer = buff.writer();

    const sstruct = try self.schema_engine.structName2SchemaStruct(struct_name);
    const to_parse = try self.allFileIndex(allocator, struct_name);

    // If there is no member to find, that mean we need to return all members, so let's populate additional data with all of them
    if (additional_data.childrens.items.len == 0)
        additional_data.populateWithEverythingExceptLink(sstruct.members, sstruct.types) catch return ZipponError.MemoryError;

    // Do I populate the relationMap directly in the thread or do I do it on the string at the end ?
    // I think it is better at the end, like that I dont need to create a deplicate of each map for the number of file
    const relation_maps = try self.schema_engine.relationMapArrayInit(allocator, struct_name, additional_data.*);

    // Open the dir that contain all files
    const dir = try self.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, sstruct.name }, .{ .access_sub_paths = false });

    // Multi thread stuffs
    var sync_context = ThreadSyncContext.init(
        additional_data.limit,
        to_parse.len,
    );

    // Do an array of writer for each thread
    // Could I create just the number of max cpu ? Because if I have 1000 files, I do 1000 list
    // But at the end, only the number of use CPU/Thread will use list simultanously
    // So I could pass list from a thread to another technicly
    var thread_writer_list = allocator.alloc(std.ArrayList(u8), to_parse.len) catch return ZipponError.MemoryError;

    // Start parsing all file in multiple thread
    for (to_parse, 0..) |file_index, i| {
        thread_writer_list[file_index] = std.ArrayList(u8).init(allocator);

        self.thread_pool.spawn(parseEntitiesOneFile, .{
            thread_writer_list[i].writer(),
            file_index,
            dir,
            sstruct.zid_schema,
            filter,
            additional_data.*,
            try self.schema_engine.structName2DataType(struct_name),
            &sync_context,
        }) catch return ZipponError.ThreadError;
    }

    // Wait for all thread to either finish or return an error
    while (!sync_context.isComplete()) std.time.sleep(100_000); // Check every 0.1ms

    // Append all writer to each other
    writer.writeByte('[') catch return ZipponError.WriteError;
    for (thread_writer_list) |list| writer.writeAll(list.items) catch return ZipponError.WriteError;
    writer.writeByte(']') catch return ZipponError.WriteError;

    // Now I need to do the relation stuff, meaning parsing new files to get the relationship value
    // Without relationship to return, this function is basically finish here

    // Here I take the JSON string and I parse it to find all {<||>} and add them to the relation map with an empty JsonString
    for (relation_maps) |*relation_map| try relation_map.populate(buff.items);

    // I then call parseEntitiesRelationMap on each
    // This will update the buff items to be the same Json but with {<|[16]u8|>} replaced with the right Json
    for (relation_maps) |*relation_map| try self.parseEntitiesRelationMap(allocator, relation_map.struct_name, relation_map, &buff);

    return buff.toOwnedSlice() catch return ZipponError.MemoryError;
}

fn parseEntitiesOneFile(
    writer: anytype,
    file_index: u64,
    dir: std.fs.Dir,
    zid_schema: []zid.DType,
    filter: ?Filter,
    additional_data: AdditionalData,
    data_types: []const DataType,
    sync_context: *ThreadSyncContext,
) void {
    var data_buffer: [config.BUFFER_SIZE]u8 = undefined;
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

// Receive a map of UUID -> empty JsonString
// Will parse the files and update the value to the JSON string of the entity that represent the key
// Will then write the input with the JSON in the map looking for {<||>}
// Once the new input received, call parseEntitiesRelationMap again the string still contain {<||>} because of sub relationship
// The buffer contain the string with {<||>} and need to be updated at the end
pub fn parseEntitiesRelationMap(
    self: *Self,
    parent_allocator: Allocator,
    struct_name: []const u8,
    relation_map: *RelationMap,
    buff: *std.ArrayList(u8),
) ZipponError!void {
    var arena = std.heap.ArenaAllocator.init(parent_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var new_buff = std.ArrayList(u8).init(allocator);
    defer new_buff.deinit();
    const writer = new_buff.writer();

    const relation_maps = try self.schema_engine.relationMapArrayInit(
        allocator,
        struct_name,
        relation_map.additional_data,
    );

    const sstruct = try self.schema_engine.structName2SchemaStruct(struct_name);
    const to_parse = try self.schema_engine.fileListToParse(allocator, struct_name, relation_map.map.*);

    // If there is no member to find, that mean we need to return all members, so let's populate additional data with all of them
    if (relation_map.additional_data.childrens.items.len == 0) {
        relation_map.additional_data.populateWithEverythingExceptLink(
            sstruct.members,
            sstruct.types,
        ) catch return ZipponError.MemoryError;
    }

    // Open the dir that contain all files
    const dir = try self.printOpenDir(
        "{s}/DATA/{s}",
        .{ self.path_to_ZipponDB_dir, sstruct.name },
        .{ .access_sub_paths = false },
    );

    // Multi thread stuffs
    var sync_context = ThreadSyncContext.init(
        relation_map.additional_data.limit,
        to_parse.len,
    );

    // Do one writer for each thread otherwise it create error by writing at the same time
    var thread_map_list = allocator.alloc(
        std.AutoHashMap([16]u8, JsonString),
        to_parse.len,
    ) catch return ZipponError.MemoryError;

    // Start parsing all file in multiple thread
    for (to_parse, 0..) |file_index, i| {
        thread_map_list[i] = relation_map.map.cloneWithAllocator(allocator) catch return ZipponError.MemoryError;

        self.thread_pool.spawn(parseEntitiesRelationMapOneFile, .{
            &thread_map_list[i],
            file_index,
            dir,
            sstruct.zid_schema,
            relation_map.additional_data,
            try self.schema_engine.structName2DataType(struct_name),
            &sync_context,
        }) catch return ZipponError.ThreadError;
    }

    // Wait for all thread to either finish or return an error
    while (!sync_context.isComplete()) std.time.sleep(100_000); // Check every 0.1ms

    // Now here I should have a list of copy of the map with all UUID a bit everywhere

    // Put all in the same map
    for (thread_map_list) |map| {
        var iter = map.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.init) relation_map.*.map.put(entry.key_ptr.*, entry.value_ptr.*) catch return ZipponError.MemoryError;
        }
    }

    // Here I write the new string and update the buff to have the new version
    try EntityWriter.updateWithRelation(writer, buff.items, relation_map.map.*);
    buff.clearRetainingCapacity();
    buff.writer().writeAll(new_buff.items) catch return ZipponError.WriteError;

    // Now here I need to iterate if buff.items still have {<||>}

    // Here I take the JSON string and I parse it to find all {<||>} and add them to the relation map with an empty JsonString
    for (relation_maps) |*sub_relation_map| try sub_relation_map.populate(buff.items);

    // I then call parseEntitiesRelationMap on each
    // This will update the buff items to be the same Json but with {<|[16]u8|>} replaced with the right Json
    for (relation_maps) |*sub_relation_map| try parseEntitiesRelationMap(self, allocator, sub_relation_map.struct_name, sub_relation_map, buff);
}

fn parseEntitiesRelationMapOneFile(
    map: *std.AutoHashMap([16]u8, JsonString),
    file_index: u64,
    dir: std.fs.Dir,
    zid_schema: []zid.DType,
    additional_data: AdditionalData,
    data_types: []const DataType,
    sync_context: *ThreadSyncContext,
) void {
    var data_buffer: [config.BUFFER_SIZE]u8 = undefined;
    var fa = std.heap.FixedBufferAllocator.init(&data_buffer);
    defer fa.reset();
    const allocator = fa.allocator();

    const parent_alloc = map.allocator;
    var string_list = std.ArrayList(u8).init(allocator);
    const writer = string_list.writer();

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
        if (!map.contains(row[0].UUID)) continue;
        defer string_list.clearRetainingCapacity();

        EntityWriter.writeEntityJSON(
            writer,
            row,
            additional_data,
            data_types,
        ) catch |err| {
            sync_context.logError("Error writing entity", err);
            return;
        };
        map.put(row[0].UUID, JsonString{
            .slice = parent_alloc.dupe(u8, string_list.items) catch |err| {
                sync_context.logError("Error duping data", err);
                return;
            },
            .init = true,
        }) catch |err| {
            sync_context.logError("Error writing entity", err);
            return;
        };

        if (sync_context.incrementAndCheckStructLimit()) break;
    }

    _ = sync_context.completeThread();
}
