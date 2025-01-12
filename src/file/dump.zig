const std = @import("std");
const zid = @import("ZipponData");
const config = @import("config");
const utils = @import("../utils.zig");
const Self = @import("core.zig").Self;
const ZipponError = @import("error").ZipponError;
const Allocator = std.mem.Allocator;
const EntityWriter = @import("../entityWriter.zig");

var path_buffer: [1024]u8 = undefined;

pub fn dumpDb(self: Self, parent_allocator: Allocator, path: []const u8, format: enum { csv, json, zid }) ZipponError!void {
    std.fs.cwd().makeDir(path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return ZipponError.CantMakeDir,
    };

    var arena = std.heap.ArenaAllocator.init(parent_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const dir = std.fs.cwd().openDir(path, .{}) catch return ZipponError.CantOpenDir;

    for (self.schema_engine.struct_array) |sstruct| {
        const file_name = std.fmt.bufPrint(&path_buffer, "{s}.{s}", .{ sstruct.name, @tagName(format) }) catch return ZipponError.MemoryError;
        const file = dir.createFile(file_name, .{}) catch return ZipponError.CantMakeFile;
        defer file.close();

        var writer = std.io.bufferedWriter(file.writer());
        EntityWriter.writeHeaderCsv(writer.writer(), sstruct.members, ';') catch return ZipponError.WriteError;

        const struct_dir = try self.printOpenDir("{s}/DATA/{s}", .{ self.path_to_ZipponDB_dir, sstruct.name }, .{});

        const file_indexs = try self.allFileIndex(allocator, sstruct.name);
        for (file_indexs) |file_index| {
            var data_buffer: [config.BUFFER_SIZE]u8 = undefined;
            var fa = std.heap.FixedBufferAllocator.init(&data_buffer);
            defer fa.reset();
            const data_allocator = fa.allocator();

            const zid_path = std.fmt.bufPrint(&path_buffer, "{d}.zid", .{file_index}) catch return ZipponError.MemoryError;

            var iter = zid.DataIterator.init(data_allocator, zid_path, struct_dir, sstruct.zid_schema) catch return ZipponError.ZipponDataError;
            while (iter.next() catch return ZipponError.ZipponDataError) |row| {
                EntityWriter.writeEntityCsv(
                    writer.writer(),
                    row,
                    sstruct.types,
                    ';',
                ) catch return ZipponError.WriteError;
            }
        }
    }
}
