const std = @import("std");
const utils = @import("../utils.zig");
const config = @import("config");
const Self = @import("core.zig").Self;
const ZipponError = @import("error").ZipponError;
const Allocator = std.mem.Allocator;
const ConditionValue = @import("../dataStructure/filter.zig").ConditionValue;
const dtype = @import("dtype");
const UUID = dtype.UUID;
const zid = @import("ZipponData");
const log = std.log.scoped(.fileEngine);

var path_buffer: [1024]u8 = undefined;

pub fn readSchemaFile(sub_path: []const u8, buffer: []u8) ZipponError!usize {
    const file = std.fs.cwd().openFile(sub_path, .{}) catch return ZipponError.CantOpenFile;
    defer file.close();

    const len = file.readAll(buffer) catch return ZipponError.ReadError;
    return len;
}

pub fn writeDbMetrics(self: *Self, buffer: *std.ArrayList(u8)) ZipponError!void {
    const main_dir = std.fs.cwd().openDir(self.path_to_ZipponDB_dir, .{ .iterate = true }) catch return ZipponError.CantOpenDir;

    const writer = buffer.writer();
    writer.print("Database path: {s}\n", .{self.path_to_ZipponDB_dir}) catch return ZipponError.WriteError;
    const main_size = getDirTotalSize(main_dir) catch 0;
    writer.print("Total size: {d:.2}Mb\n", .{@as(f64, @floatFromInt(main_size)) / 1024.0 / 1024.0}) catch return ZipponError.WriteError;

    writer.print("CPU core: {d}\n", .{config.CPU_CORE}) catch return ZipponError.WriteError;
    writer.print("Max file size: {d:.2}Mb\n", .{@as(f64, @floatFromInt(config.MAX_FILE_SIZE)) / 1024.0 / 1024.0}) catch return ZipponError.WriteError;

    const log_dir = main_dir.openDir("LOG", .{ .iterate = true }) catch return ZipponError.CantOpenDir;
    const log_size = getDirTotalSize(log_dir) catch 0;
    writer.print("LOG: {d:.2}Mb\n", .{@as(f64, @floatFromInt(log_size)) / 1024.0 / 1024.0}) catch return ZipponError.WriteError;

    const backup_dir = main_dir.openDir("BACKUP", .{ .iterate = true }) catch return ZipponError.CantOpenDir;
    const backup_size = getDirTotalSize(backup_dir) catch 0;
    writer.print("BACKUP: {d:.2}Mb\n", .{@as(f64, @floatFromInt(backup_size)) / 1024.0 / 1024.0}) catch return ZipponError.WriteError;

    const data_dir = main_dir.openDir("DATA", .{ .iterate = true }) catch return ZipponError.CantOpenDir;
    const data_size = getDirTotalSize(data_dir) catch 0;
    writer.print("DATA: {d:.2}Mb\n", .{@as(f64, @floatFromInt(data_size)) / 1024.0 / 1024.0}) catch return ZipponError.WriteError;

    var iter = data_dir.iterate();
    while (iter.next() catch return ZipponError.DirIterError) |entry| {
        if (entry.kind != .directory) continue;
        const sub_dir = data_dir.openDir(entry.name, .{ .iterate = true }) catch return ZipponError.CantOpenDir;
        const size = getDirTotalSize(sub_dir) catch 0;
        const result = try self.getNumberOfEntityAndFile(entry.name);
        writer.print("  {s}: {d:.2}Mb | {d} entities | {d} files\n", .{
            entry.name,
            @as(f64, @floatFromInt(size)) / 1024.0 / 1024.0,
            result.entity,
            result.file,
        }) catch return ZipponError.WriteError;
    }
}

pub fn getDirTotalSize(dir: std.fs.Dir) !u64 {
    var total: u64 = 0;
    var stat: std.fs.File.Stat = undefined;
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .directory) {
            const sub_dir = try dir.openDir(entry.name, .{ .iterate = true });
            total += try getDirTotalSize(sub_dir);
        }

        if (entry.kind != .file) continue;
        stat = try dir.statFile(entry.name);
        total += stat.size;
    }
    return total;
}

pub fn string2Data(allocator: Allocator, value: ConditionValue) ZipponError!zid.Data {
    switch (value) {
        .int => |v| return zid.Data.initInt(v),
        .float => |v| return zid.Data.initFloat(v),
        .bool_ => |v| return zid.Data.initBool(v),
        .unix => |v| return zid.Data.initUnix(v),
        .str => |v| return zid.Data.initStr(v),
        .link => |v| {
            if (v.count() > 0) {
                var iter = v.keyIterator();
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
            return zid.Data.initUUIDArray(zid.allocEncodArray.UUID(allocator, items.items) catch return ZipponError.AllocEncodError);
        },
        .self => |v| return zid.Data.initUUID(v.bytes),
        .int_array => |v| return zid.Data.initIntArray(zid.allocEncodArray.Int(allocator, v) catch return ZipponError.AllocEncodError),
        .float_array => |v| return zid.Data.initFloatArray(zid.allocEncodArray.Float(allocator, v) catch return ZipponError.AllocEncodError),
        .str_array => |v| return zid.Data.initStrArray(zid.allocEncodArray.Str(allocator, v) catch return ZipponError.AllocEncodError),
        .bool_array => |v| return zid.Data.initBoolArray(zid.allocEncodArray.Bool(allocator, v) catch return ZipponError.AllocEncodError),
        .unix_array => |v| return zid.Data.initUnixArray(zid.allocEncodArray.Unix(allocator, v) catch return ZipponError.AllocEncodError),
    }
}

/// Take a map from the parseNewData and return an ordered array of Data to be use in a DataWriter
pub fn orderedNewData(
    self: *Self,
    allocator: Allocator,
    struct_name: []const u8,
    map: std.StringHashMap(ConditionValue),
) ZipponError![]zid.Data {
    const members = try self.schema_engine.structName2structMembers(struct_name);
    var datas = allocator.alloc(zid.Data, (members.len)) catch return ZipponError.MemoryError;

    const new_uuid = UUID.init();
    datas[0] = zid.Data.initUUID(new_uuid.bytes);

    for (members, 0..) |member, i| {
        if (i == 0) continue; // Skip the id
        datas[i] = try string2Data(allocator, map.get(member).?);
    }

    return datas;
}

/// Get the index of the first file that is bellow the size limit. If not found, create a new file
/// TODO: Need some serious speed up. I should keep in memory a file->size as a hashmap and use that instead
pub fn getFirstUsableIndexFile(self: Self, struct_name: []const u8) ZipponError!usize {
    var member_dir = try self.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, struct_name }, .{ .iterate = true });
    defer member_dir.close();

    var i: usize = 0;
    var iter = member_dir.iterate();
    while (iter.next() catch return ZipponError.DirIterError) |entry| {
        i += 1;
        const file_stat = member_dir.statFile(entry.name) catch return ZipponError.FileStatError;
        if (file_stat.size < config.MAX_FILE_SIZE) {
            // Cant I just return i ? It is supossed that files are ordered. I think I already check and it is not
            log.debug("{s}\n\n", .{entry.name});
            return std.fmt.parseInt(usize, entry.name[0..(entry.name.len - 4)], 10) catch return ZipponError.InvalidFileIndex; // INFO: Hardcoded len of file extension
        }
    }

    const path = std.fmt.bufPrint(&path_buffer, "{s}/DATA/{s}/{d}.zid", .{ self.path_to_ZipponDB_dir, struct_name, i }) catch return ZipponError.MemoryError;
    zid.createFile(path, null) catch return ZipponError.ZipponDataError;

    return i;
}

/// Iterate over all file of a struct and return the index of the last file.
/// E.g. a struct with 0.csv and 1.csv it return 1.
/// FIXME: I use 0..file_index but because now I delete empty file, I can end up trying to parse an empty file. So I need to delete that
/// And do something that return a list of file to parse instead
pub fn maxFileIndex(self: Self, struct_name: []const u8) ZipponError!usize {
    var dir = try self.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, struct_name }, .{ .iterate = true });
    defer dir.close();

    var count: usize = 0;

    var iter = dir.iterate();
    while (iter.next() catch return ZipponError.DirIterError) |entry| {
        if (entry.kind != .file) continue;
        count += 1;
    }
    return count - 1;
}

pub fn allFileIndex(self: Self, allocator: Allocator, struct_name: []const u8) ZipponError![]usize {
    var dir = try self.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, struct_name }, .{ .iterate = true });
    defer dir.close();

    var array = std.ArrayList(usize).init(allocator);

    var iter = dir.iterate();
    while (iter.next() catch return ZipponError.DirIterError) |entry| {
        if (entry.kind != .file) continue;
        const index = std.fmt.parseInt(usize, entry.name[0..(entry.name.len - 4)], 10) catch return ZipponError.InvalidFileIndex;
        array.append(index) catch return ZipponError.MemoryError;
    }
    return array.toOwnedSlice() catch return ZipponError.MemoryError;
}

pub fn isSchemaFileInDir(self: *Self) bool {
    _ = self.printOpenFile("{s}/schema", .{self.path_to_ZipponDB_dir}, .{}) catch return false;
    return true;
}

pub fn writeSchemaFile(self: *Self, null_terminated_schema_buff: [:0]const u8) ZipponError!void {
    var zippon_dir = std.fs.cwd().openDir(self.path_to_ZipponDB_dir, .{}) catch return ZipponError.MemoryError;
    defer zippon_dir.close();

    zippon_dir.deleteFile("schema") catch |err| switch (err) {
        error.FileNotFound => {},
        else => return ZipponError.DeleteFileError,
    };

    var file = zippon_dir.createFile("schema", .{}) catch return ZipponError.CantMakeFile;
    defer file.close();
    file.writeAll(null_terminated_schema_buff) catch return ZipponError.WriteError;
}

pub fn printOpenDir(_: Self, comptime format: []const u8, args: anytype, options: std.fs.Dir.OpenDirOptions) ZipponError!std.fs.Dir {
    const path = std.fmt.bufPrint(&path_buffer, format, args) catch return ZipponError.CantOpenDir;
    return std.fs.cwd().openDir(path, options) catch ZipponError.CantOpenDir;
}

pub fn printOpenFile(_: Self, comptime format: []const u8, args: anytype, options: std.fs.File.OpenFlags) ZipponError!std.fs.File {
    const path = std.fmt.bufPrint(&path_buffer, format, args) catch return ZipponError.CantOpenDir;
    return std.fs.cwd().openFile(path, options) catch ZipponError.CantOpenFile;
}
