const std = @import("std");
const Allocator = std.mem.Allocator;
const SchemaStruct = @import("schemaParser.zig").Parser.SchemaStruct;
const Parser = @import("schemaParser.zig").Parser;
const Tokenizer = @import("tokenizers/schema.zig").Tokenizer;
const ZipponError = @import("stuffs/errors.zig").ZipponError;
const dtype = @import("dtype");
const DataType = dtype.DataType;
const FileEngine = @import("fileEngine.zig").FileEngine;

const config = @import("config.zig");
const BUFFER_SIZE = config.BUFFER_SIZE;

const log = std.log.scoped(.schemaEngine);

/// Manage everything that is relate to the schema
/// This include keeping in memory the schema and schema file, and some functions to get like all members of a specific struct.
/// For now it is a bit empty. But this is where I will manage migration
pub const SchemaEngine = struct {
    allocator: Allocator,
    null_terminated_schema_buff: [:0]u8,
    struct_array: []SchemaStruct,

    // The path is the path to the schema file
    pub fn init(allocator: Allocator, path: []const u8, file_engine: *FileEngine) ZipponError!SchemaEngine {
        log.debug("Trying to init a SchemaEngine with path {s}", .{path});
        var schema_buf = allocator.alloc(u8, BUFFER_SIZE) catch return ZipponError.MemoryError;
        defer allocator.free(schema_buf);

        const len: usize = try FileEngine.readSchemaFile(path, schema_buf);
        const null_terminated_schema_buff = allocator.dupeZ(u8, schema_buf[0..len]) catch return ZipponError.MemoryError;
        errdefer allocator.free(null_terminated_schema_buff);

        var toker = Tokenizer.init(null_terminated_schema_buff);
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

        return SchemaEngine{
            .allocator = allocator,
            .null_terminated_schema_buff = null_terminated_schema_buff,
            .struct_array = struct_array.toOwnedSlice() catch return ZipponError.MemoryError,
        };
    }

    pub fn deinit(self: *SchemaEngine) void {
        for (self.struct_array) |*elem| elem.deinit();
        self.allocator.free(self.struct_array);
        self.allocator.free(self.null_terminated_schema_buff);
    }

    /// Get the type of the member
    pub fn memberName2DataType(self: *SchemaEngine, struct_name: []const u8, member_name: []const u8) ZipponError!DataType {
        var i: usize = 0;

        for (try self.structName2structMembers(struct_name)) |mn| {
            const dtypes = try self.structName2DataType(struct_name);
            if (std.mem.eql(u8, mn, member_name)) return dtypes[i];
            i += 1;
        }

        return ZipponError.MemberNotFound;
    }

    pub fn memberName2DataIndex(self: *SchemaEngine, struct_name: []const u8, member_name: []const u8) ZipponError!usize {
        var i: usize = 0;

        for (try self.structName2structMembers(struct_name)) |mn| {
            if (std.mem.eql(u8, mn, member_name)) return i;
            i += 1;
        }

        return ZipponError.MemberNotFound;
    }

    /// Get the list of all member name for a struct name
    pub fn structName2structMembers(self: *SchemaEngine, struct_name: []const u8) ZipponError![][]const u8 {
        var i: usize = 0;

        while (i < self.struct_array.len) : (i += 1) if (std.mem.eql(u8, self.struct_array[i].name, struct_name)) break;

        if (i == self.struct_array.len) {
            return ZipponError.StructNotFound;
        }

        return self.struct_array[i].members;
    }

    pub fn structName2SchemaStruct(self: *SchemaEngine, struct_name: []const u8) ZipponError!SchemaStruct {
        var i: usize = 0;

        while (i < self.struct_array.len) : (i += 1) if (std.mem.eql(u8, self.struct_array[i].name, struct_name)) break;

        if (i == self.struct_array.len) {
            return ZipponError.StructNotFound;
        }

        return self.struct_array[i];
    }

    pub fn structName2DataType(self: *SchemaEngine, struct_name: []const u8) ZipponError![]const DataType {
        var i: u16 = 0;

        while (i < self.struct_array.len) : (i += 1) {
            if (std.mem.eql(u8, self.struct_array[i].name, struct_name)) break;
        }

        if (i == self.struct_array.len and !std.mem.eql(u8, self.struct_array[i].name, struct_name)) {
            return ZipponError.StructNotFound;
        }

        return self.struct_array[i].types;
    }

    /// Chech if the name of a struct is in the current schema
    pub fn isStructNameExists(self: *SchemaEngine, struct_name: []const u8) bool {
        var i: u16 = 0;
        log.debug("\n\n{any}\n\n", .{self.struct_array});
        while (i < self.struct_array.len) : (i += 1) if (std.mem.eql(u8, self.struct_array[i].name, struct_name)) return true;
        return false;
    }

    /// Check if a struct have the member name
    pub fn isMemberNameInStruct(self: *SchemaEngine, struct_name: []const u8, member_name: []const u8) ZipponError!bool {
        for (try self.structName2structMembers(struct_name)) |mn| {
            if (std.mem.eql(u8, mn, member_name)) return true;
        }
        return false;
    }

    // Return true if the map have all the member name as key and not more
    pub fn checkIfAllMemberInMap(
        self: *SchemaEngine,
        struct_name: []const u8,
        map: *std.StringHashMap([]const u8),
        error_message_buffer: *std.ArrayList(u8),
    ) ZipponError!bool {
        const all_struct_member = try self.structName2structMembers(struct_name);
        var count: u16 = 0;

        const writer = error_message_buffer.writer();

        for (all_struct_member) |mn| {
            if (std.mem.eql(u8, mn, "id")) continue;
            if (map.contains(mn)) count += 1 else writer.print(" {s},", .{mn}) catch return ZipponError.WriteError;
        }

        return ((count == all_struct_member.len - 1) and (count == map.count()));
    }
};
