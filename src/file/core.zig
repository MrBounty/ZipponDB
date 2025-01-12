const std = @import("std");
const Pool = std.Thread.Pool;
const SchemaEngine = @import("../schema/core.zig");

const ZipponError = @import("error").ZipponError;
const log = std.log.scoped(.fileEngine);

var path_to_ZipponDB_dir_buffer: [1024]u8 = undefined;

/// Manage everything that is relate to read or write in files
/// Or even get stats, whatever. If it touch files, it's here
pub const Self = @This();

// This basically expend the file with other
// So I can define function in other file for the same struct
pub usingnamespace @import("utils.zig");
pub usingnamespace @import("directory.zig");
pub usingnamespace @import("read.zig");
pub usingnamespace @import("write.zig");
pub usingnamespace @import("dump.zig");

path_to_ZipponDB_dir: []const u8,
thread_pool: *Pool, // same pool as the ThreadEngine
schema_engine: SchemaEngine = undefined, // This is init after the FileEngine and I attach after. Do I need to init after tho ?

pub fn init(path: []const u8, thread_pool: *Pool) ZipponError!Self {
    return Self{
        .path_to_ZipponDB_dir = std.fmt.bufPrint(&path_to_ZipponDB_dir_buffer, "{s}", .{path}) catch return ZipponError.MemoryError,
        .thread_pool = thread_pool,
    };
}
