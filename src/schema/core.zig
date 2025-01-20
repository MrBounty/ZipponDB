const std = @import("std");
const config = @import("config");
const Allocator = std.mem.Allocator;
const SchemaStruct = @import("struct.zig");
const FileEngine = @import("../file/core.zig");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Parser = @import("parser.zig").Parser;

const ZipponError = @import("error").ZipponError;
const log = std.log.scoped(.schemaEngine);

/// Manage everything that is relate to the schema
/// This include keeping in memory the schema and schema file, and some functions to get like all members of a specific struct.
pub const Self = @This();

var schema_buffer: [config.BUFFER_SIZE]u8 = undefined;

pub usingnamespace @import("utils.zig");

arena: *std.heap.ArenaAllocator,
allocator: Allocator,
struct_array: []SchemaStruct,
null_terminated: [:0]u8,

pub fn init(parent_allocator: Allocator, path: []const u8, file_engine: *FileEngine) ZipponError!Self {
    const arena = parent_allocator.create(std.heap.ArenaAllocator) catch return ZipponError.MemoryError;
    arena.* = std.heap.ArenaAllocator.init(parent_allocator);
    const allocator = arena.allocator();

    var buffer: [config.BUFFER_SIZE]u8 = undefined;

    log.debug("Trying to init a SchemaEngine with path {s}", .{path});
    const len: usize = try FileEngine.readSchemaFile(path, &buffer);
    const null_terminated = std.fmt.bufPrintZ(&schema_buffer, "{s}", .{buffer[0..len]}) catch return ZipponError.MemoryError;

    var toker = Tokenizer.init(null_terminated);
    var parser = Parser.init(&toker, allocator);

    var struct_array = std.ArrayList(SchemaStruct).init(allocator);
    errdefer struct_array.deinit();
    parser.parse(&struct_array) catch return ZipponError.SchemaNotConform;

    log.debug("SchemaEngine init with {d} SchemaStruct.", .{struct_array.items.len});

    for (struct_array.items) |sstruct| {
        file_engine.populateFileIndexUUIDMap(sstruct, sstruct.uuid_file_index) catch |err| {
            log.err("Error populate file index UUID map {any}", .{err});
        };
    }

    return Self{
        .arena = arena,
        .allocator = allocator,
        .struct_array = struct_array.toOwnedSlice() catch return ZipponError.MemoryError,
        .null_terminated = null_terminated,
    };
}

pub fn deinit(self: *Self) void {
    const parent_allocator = self.arena.child_allocator;
    self.arena.deinit();
    parent_allocator.destroy(self.arena);
}
