const std = @import("std");
const config = @import("config");
const utils = @import("../utils.zig");
const zid = @import("ZipponData");
const Self = @import("core.zig").Self;
const ZipponError = @import("error").ZipponError;
const SchemaStruct = @import("../schema/struct.zig");

var path_buffer: [1024]u8 = undefined;

/// Create the main folder. Including DATA, LOG and BACKUP
pub fn createMainDirectories(self: *Self) ZipponError!void {
    var path_buff = std.fmt.bufPrint(&path_buffer, "{s}", .{self.path_to_ZipponDB_dir}) catch return ZipponError.MemoryError;

    const cwd = std.fs.cwd();

    cwd.makeDir(path_buff) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return ZipponError.CantMakeDir,
    };

    path_buff = std.fmt.bufPrint(&path_buffer, "{s}/DATA", .{self.path_to_ZipponDB_dir}) catch return ZipponError.MemoryError;

    cwd.makeDir(path_buff) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return ZipponError.CantMakeDir,
    };

    path_buff = std.fmt.bufPrint(&path_buffer, "{s}/BACKUP", .{self.path_to_ZipponDB_dir}) catch return ZipponError.MemoryError;

    cwd.makeDir(path_buff) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return ZipponError.CantMakeDir,
    };

    path_buff = std.fmt.bufPrint(&path_buffer, "{s}/LOG", .{self.path_to_ZipponDB_dir}) catch return ZipponError.MemoryError;

    cwd.makeDir(path_buff) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return ZipponError.CantMakeDir,
    };

    path_buff = std.fmt.bufPrint(&path_buffer, "{s}/LOG/log", .{self.path_to_ZipponDB_dir}) catch return ZipponError.MemoryError;

    if (config.RESET_LOG_AT_RESTART) {
        _ = cwd.createFile(path_buff, .{}) catch return ZipponError.CantMakeFile;
    } else {
        _ = std.fs.cwd().openFile(path_buff, .{}) catch {
            _ = cwd.createFile(path_buff, .{}) catch return ZipponError.CantMakeFile;
        };
    }
}

/// Request a path to a schema file and then create the struct folder
/// TODO: Check if some data already exist and if so ask if the user want to delete it and make a backup
pub fn createStructDirectories(self: *Self, struct_array: []SchemaStruct) ZipponError!void {
    var data_dir = try self.printOpenDir("{s}/DATA", .{self.path_to_ZipponDB_dir}, .{});
    defer data_dir.close();

    for (struct_array) |schema_struct| {
        data_dir.makeDir(schema_struct.name) catch |err| switch (err) {
            error.PathAlreadyExists => continue,
            else => return ZipponError.CantMakeDir,
        };
        const struct_dir = data_dir.openDir(schema_struct.name, .{}) catch return ZipponError.CantOpenDir;

        zid.createFile("0.zid", struct_dir) catch return ZipponError.CantMakeFile;
    }
}
