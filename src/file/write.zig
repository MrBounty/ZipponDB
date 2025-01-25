const std = @import("std");
const config = @import("config");
const utils = @import("../utils.zig");
const zid = @import("ZipponData");
const updateData = @import("array.zig").updateData;
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
const ValueOrArray = @import("../ziql/parts/newData.zig").ValueOrArray;

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
    maps: []std.StringHashMap(ValueOrArray),
    writer: anytype,
) ZipponError!void {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
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

const UpdatePosibility = enum { fix, vari, stay };

pub fn updateEntities(
    self: *Self,
    struct_name: []const u8,
    filter: ?Filter,
    map: std.StringHashMap(ValueOrArray),
    writer: anytype, // TODO: Stop using writer and use an allocator + toOwnedSlice like parseEntities
    additional_data: *AdditionalData,
) ZipponError!void {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    var safe_allocator = std.heap.ThreadSafeAllocator{ .child_allocator = arena.allocator() };
    const allocator = safe_allocator.allocator();

    const sstruct = try self.schema_engine.structName2SchemaStruct(struct_name);

    const dir = try self.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, sstruct.name }, .{});
    const to_parse = try self.allFileIndex(allocator, struct_name);

    // Multi-threading setup
    var sync_context = ThreadSyncContext.init(additional_data.limit);

    // Create a thread-safe writer for each file
    var thread_writer_list = allocator.alloc(std.ArrayList(u8), to_parse.len) catch return ZipponError.MemoryError;
    for (thread_writer_list) |*list| {
        list.* = std.ArrayList(u8).init(allocator);
    }

    var index_switch = std.ArrayList(UpdatePosibility).init(allocator);
    defer index_switch.deinit();

    // If the member name is not in the map, it stay
    // Otherwise it need to be update. For that 2 scenarios:
    // - Update all entities with a const .fix
    // - Update entities base on themself .vari
    // FIXME: I'm not sure that id is in the array, need to check, also need to check to prevent updating it
    for (sstruct.members) |member| {
        if (map.get(member)) |voa| {
            switch (voa) {
                .value => index_switch.append(.fix) catch return ZipponError.MemoryError,
                .array => index_switch.append(.vari) catch return ZipponError.MemoryError,
            }
        } else {
            index_switch.append(.stay) catch return ZipponError.MemoryError;
        }
    }

    // Spawn threads for each file
    var wg: std.Thread.WaitGroup = .{};
    for (to_parse, 0..) |file_index, i| self.thread_pool.spawnWg(
        &wg,
        updateEntitiesOneFile,
        .{
            sstruct,
            filter,
            map,
            index_switch.items,
            thread_writer_list[i].writer(),
            file_index,
            dir,
            &sync_context,
        },
    );
    wg.wait();

    // Combine results
    writer.writeByte('[') catch return ZipponError.WriteError;
    for (thread_writer_list) |list| {
        writer.writeAll(list.items) catch return ZipponError.WriteError;
    }
    writer.writeByte(']') catch return ZipponError.WriteError;
}

fn updateEntitiesOneFile(
    sstruct: SchemaStruct,
    filter: ?Filter,
    map: std.StringHashMap(ValueOrArray),
    index_switch: []UpdatePosibility,
    writer: anytype,
    file_index: u64,
    dir: std.fs.Dir,
    sync_context: *ThreadSyncContext,
) void {
    var data_buffer: [config.BUFFER_SIZE]u8 = undefined;
    var fa = std.heap.FixedBufferAllocator.init(&data_buffer);
    defer fa.reset();
    const allocator = fa.allocator();

    var new_data_buff = allocator.alloc(zid.Data, index_switch.len) catch return;

    // First I fill the one that are updated by a const
    for (index_switch, 0..) |is, i| switch (is) {
        .fix => new_data_buff[i] = @import("utils.zig").string2Data(allocator, map.get(sstruct.members[i]).?.value) catch return,
        else => {},
    };

    const path = std.fmt.bufPrint(&path_buffer, "{d}.zid", .{file_index}) catch return;

    var iter = zid.DataIterator.init(allocator, path, dir, sstruct.zid_schema) catch return;
    defer iter.deinit();

    const new_path = std.fmt.allocPrint(allocator, "{d}.zid.new", .{file_index}) catch return;
    defer allocator.free(new_path);

    zid.createFile(new_path, dir) catch return;

    var new_writer = zid.DataWriter.init(new_path, dir) catch {
        zid.deleteFile(new_path, dir) catch {};
        return;
    };
    defer new_writer.deinit();

    var finish_writing = false;
    while (iter.next() catch return) |row| {
        if (!finish_writing and (filter == null or filter.?.evaluate(row))) {
            // Add the unchanged Data in the new_data_buff
            for (index_switch, 0..) |is, i| switch (is) {
                .stay => new_data_buff[i] = row[i],
                .vari => {
                    const x = map.get(sstruct.members[i]).?.array;
                    updateData(allocator, x.condition, &row[i], x.data) catch {
                        zid.deleteFile(new_path, dir) catch {};
                        return;
                    };
                },
                else => {},
            };

            log.debug("{d} {any}\n\n", .{ new_data_buff.len, new_data_buff });

            new_writer.write(new_data_buff) catch {
                zid.deleteFile(new_path, dir) catch {};
                return;
            };

            writer.print("\"{s}\",", .{UUID.format_bytes(row[0].UUID)}) catch {
                zid.deleteFile(new_path, dir) catch {};
                return;
            };

            finish_writing = sync_context.incrementAndCheckStructLimit();
        } else {
            new_writer.write(row) catch {
                zid.deleteFile(new_path, dir) catch {};
                return;
            };
        }
    }

    new_writer.flush() catch return;
    dir.deleteFile(path) catch return;
    dir.rename(new_path, path) catch return;
}

/// Delete all entity based on the filter. Will also write a JSON format list of all UUID deleted into the buffer
pub fn deleteEntities(
    self: *Self,
    struct_name: []const u8,
    filter: ?Filter,
    writer: anytype,
    additional_data: *AdditionalData,
) ZipponError!void {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    var safe_allocator = std.heap.ThreadSafeAllocator{ .child_allocator = arena.allocator() };
    const allocator = safe_allocator.allocator();

    const sstruct = try self.schema_engine.structName2SchemaStruct(struct_name);

    const dir = try self.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, sstruct.name }, .{});
    const to_parse = try self.allFileIndex(allocator, struct_name);

    // Multi-threading setup
    var sync_context = ThreadSyncContext.init(additional_data.limit);

    // Create a thread-safe writer for each file
    var thread_writer_list = allocator.alloc(std.ArrayList(u8), to_parse.len) catch return ZipponError.MemoryError;

    // Spawn threads for each file
    var wg: std.Thread.WaitGroup = .{};
    for (to_parse, 0..) |file_index, i| {
        thread_writer_list[i] = std.ArrayList(u8).init(allocator);
        self.thread_pool.spawnWg(
            &wg,
            deleteEntitiesOneFile,
            .{
                thread_writer_list[i].writer(),
                file_index,
                dir,
                sstruct.zid_schema,
                filter,
                &sync_context,
            },
        );
    }
    wg.wait();

    // Combine results
    writer.writeByte('[') catch return ZipponError.WriteError;
    for (thread_writer_list) |list| {
        writer.writeAll(list.items) catch return ZipponError.WriteError;
    }
    writer.writeByte(']') catch return ZipponError.WriteError;

    //  FIXME: Stop doing that and just remove UUID from the map itself instead of reparsing everything at the end
    //  It's just that I can't do it in deleteEntitiesOneFile itself
    sstruct.uuid_file_index.map.clearRetainingCapacity();
    _ = sstruct.uuid_file_index.reset();
    try self.populateFileIndexUUIDMap(sstruct, sstruct.uuid_file_index);
}

fn deleteEntitiesOneFile(
    writer: anytype,
    file_index: u64,
    dir: std.fs.Dir,
    zid_schema: []zid.DType,
    filter: ?Filter,
    sync_context: *ThreadSyncContext,
) void {
    var data_buffer: [config.BUFFER_SIZE]u8 = undefined;
    var fa = std.heap.FixedBufferAllocator.init(&data_buffer);
    defer fa.reset();
    const allocator = fa.allocator();

    const path = std.fmt.allocPrint(allocator, "{d}.zid", .{file_index}) catch return;

    var iter = zid.DataIterator.init(allocator, path, dir, zid_schema) catch return;
    defer iter.deinit();

    const new_path = std.fmt.allocPrint(allocator, "{d}.zid.new", .{file_index}) catch return;
    zid.createFile(new_path, dir) catch return;

    var new_writer = zid.DataWriter.init(new_path, dir) catch return;
    errdefer new_writer.deinit();

    var finish_writing = false;
    while (iter.next() catch return) |row| {
        if (!finish_writing and (filter == null or filter.?.evaluate(row))) {
            writer.print("{{\"{s}\"}},", .{UUID.format_bytes(row[0].UUID)}) catch return;
            finish_writing = sync_context.incrementAndCheckStructLimit();
        } else {
            new_writer.write(row) catch return;
        }
    }

    new_writer.flush() catch return;

    dir.deleteFile(path) catch return;

    const file_stat = new_writer.fileStat() catch return;
    new_writer.deinit();
    if (file_index != 0 and file_stat.size == 0) {
        dir.deleteFile(new_path) catch return;
    } else {
        dir.rename(new_path, path) catch return;
    }
}
