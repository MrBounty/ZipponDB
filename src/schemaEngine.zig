const std = @import("std");
const zid = @import("ZipponData");
const Allocator = std.mem.Allocator;
const Parser = @import("schemaParser.zig").Parser;
const Tokenizer = @import("tokenizers/schema.zig").Tokenizer;
const ZipponError = @import("stuffs/errors.zig").ZipponError;
const dtype = @import("dtype");
const DataType = dtype.DataType;
const AdditionalData = @import("stuffs/additionalData.zig").AdditionalData;
const RelationMap = @import("stuffs/relationMap.zig").RelationMap;
const JsonString = @import("stuffs/relationMap.zig").JsonString;
const ConditionValue = @import("stuffs/filter.zig").ConditionValue;
const UUID = dtype.UUID;
const UUIDFileIndex = @import("stuffs/UUIDFileIndex.zig").UUIDIndexMap;
const FileEngine = @import("fileEngine.zig").FileEngine;

// TODO: Create a schemaEngine directory and add this as core and the parser with it

const config = @import("config");
const BUFFER_SIZE = config.BUFFER_SIZE;

var schema_buffer: [BUFFER_SIZE]u8 = undefined;

// TODO: Stop keeping the allocator at the root of the file
var arena: std.heap.ArenaAllocator = undefined;
var allocator: Allocator = undefined;

const log = std.log.scoped(.schemaEngine);

pub const SchemaStruct = struct {
    name: []const u8,
    members: [][]const u8,
    types: []DataType,
    zid_schema: []zid.DType,
    links: std.StringHashMap([]const u8), // Map key as member_name and value as struct_name of the link
    uuid_file_index: *UUIDFileIndex, // Map UUID to the index of the file store in

    pub fn init(
        name: []const u8,
        members: [][]const u8,
        types: []DataType,
        links: std.StringHashMap([]const u8),
    ) ZipponError!SchemaStruct {
        const uuid_file_index = allocator.create(UUIDFileIndex) catch return ZipponError.MemoryError;
        uuid_file_index.* = UUIDFileIndex.init(allocator) catch return ZipponError.MemoryError;
        return SchemaStruct{
            .name = name,
            .members = members,
            .types = types,
            .zid_schema = SchemaStruct.fileDataSchema(types) catch return ZipponError.MemoryError,
            .links = links,
            .uuid_file_index = uuid_file_index,
        };
    }

    fn fileDataSchema(dtypes: []DataType) ZipponError![]zid.DType {
        var schema = std.ArrayList(zid.DType).init(allocator);

        for (dtypes) |dt| {
            schema.append(switch (dt) {
                .int => .Int,
                .float => .Float,
                .str => .Str,
                .bool => .Bool,
                .link => .UUID,
                .self => .UUID,
                .date => .Unix,
                .time => .Unix,
                .datetime => .Unix,
                .int_array => .IntArray,
                .float_array => .FloatArray,
                .str_array => .StrArray,
                .bool_array => .BoolArray,
                .date_array => .UnixArray,
                .time_array => .UnixArray,
                .datetime_array => .UnixArray,
                .link_array => .UUIDArray,
            }) catch return ZipponError.MemoryError;
        }
        return schema.toOwnedSlice() catch return ZipponError.MemoryError;
    }
};

/// Manage everything that is relate to the schema
/// This include keeping in memory the schema and schema file, and some functions to get like all members of a specific struct.
/// For now it is a bit empty. But this is where I will manage migration
pub const SchemaEngine = struct {
    struct_array: []SchemaStruct,
    null_terminated: [:0]u8,

    // The path is the path to the schema file
    pub fn init(path: []const u8, file_engine: *FileEngine) ZipponError!SchemaEngine {
        arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        allocator = arena.allocator();

        var buffer: [BUFFER_SIZE]u8 = undefined;

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

        return SchemaEngine{
            .struct_array = struct_array.toOwnedSlice() catch return ZipponError.MemoryError,
            .null_terminated = null_terminated,
        };
    }

    pub fn deinit(_: SchemaEngine) void {
        arena.deinit();
    }

    /// Get the type of the member
    pub fn memberName2DataType(self: *SchemaEngine, struct_name: []const u8, member_name: []const u8) ZipponError!DataType {
        for (try self.structName2structMembers(struct_name), 0..) |mn, i| {
            const dtypes = try self.structName2DataType(struct_name);
            if (std.mem.eql(u8, mn, member_name)) return dtypes[i];
        }

        return ZipponError.MemberNotFound;
    }

    pub fn memberName2DataIndex(self: *SchemaEngine, struct_name: []const u8, member_name: []const u8) ZipponError!usize {
        for (try self.structName2structMembers(struct_name), 0..) |mn, i| {
            if (std.mem.eql(u8, mn, member_name)) return i;
        }

        return ZipponError.MemberNotFound;
    }

    /// Get the list of all member name for a struct name
    pub fn structName2structMembers(self: SchemaEngine, struct_name: []const u8) ZipponError![][]const u8 {
        var i: usize = 0;

        while (i < self.struct_array.len) : (i += 1) if (std.mem.eql(u8, self.struct_array[i].name, struct_name)) break;

        if (i == self.struct_array.len) {
            return ZipponError.StructNotFound;
        }

        return self.struct_array[i].members;
    }

    pub fn structName2SchemaStruct(self: SchemaEngine, struct_name: []const u8) ZipponError!SchemaStruct {
        var i: usize = 0;

        while (i < self.struct_array.len) : (i += 1) if (std.mem.eql(u8, self.struct_array[i].name, struct_name)) break;

        if (i == self.struct_array.len) {
            return ZipponError.StructNotFound;
        }

        return self.struct_array[i];
    }

    pub fn structName2DataType(self: SchemaEngine, struct_name: []const u8) ZipponError![]const DataType {
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
    pub fn isStructNameExists(self: SchemaEngine, struct_name: []const u8) bool {
        var i: u16 = 0;
        while (i < self.struct_array.len) : (i += 1) if (std.mem.eql(u8, self.struct_array[i].name, struct_name)) return true;
        return false;
    }

    /// Check if a struct have the member name
    pub fn isMemberNameInStruct(self: SchemaEngine, struct_name: []const u8, member_name: []const u8) ZipponError!bool {
        for (try self.structName2structMembers(struct_name)) |mn| {
            if (std.mem.eql(u8, mn, member_name)) return true;
        }
        return false;
    }

    /// Return the SchemaStruct of the struct that the member is linked. So if it is not a link, it is itself, if it is a link, it the the sstruct of the link
    pub fn linkedStructName(self: SchemaEngine, struct_name: []const u8, member_name: []const u8) ZipponError!SchemaStruct {
        const sstruct = try self.structName2SchemaStruct(struct_name);
        if (sstruct.links.get(member_name)) |struct_link_name| {
            return try self.structName2SchemaStruct(struct_link_name);
        }
        return sstruct;
    }

    // Return true if the map have all the member name as key and not more
    pub fn checkIfAllMemberInMap(
        self: SchemaEngine,
        struct_name: []const u8,
        map: *std.StringHashMap(ConditionValue),
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

    pub fn isUUIDExist(self: SchemaEngine, struct_name: []const u8, uuid: UUID) bool {
        const sstruct = self.structName2SchemaStruct(struct_name) catch return false;
        return sstruct.uuid_file_index.contains(uuid);
    }

    /// Create an array of empty RelationMap based on the additionalData
    pub fn relationMapArrayInit(
        self: SchemaEngine,
        alloc: Allocator,
        struct_name: []const u8,
        additional_data: AdditionalData,
    ) ZipponError![]RelationMap {
        // So here I should have relationship if children are relations
        var array = std.ArrayList(RelationMap).init(alloc);
        const sstruct = try self.structName2SchemaStruct(struct_name);
        for (additional_data.childrens.items) |child| if (sstruct.links.contains(child.name)) {
            const map = alloc.create(std.AutoHashMap([16]u8, JsonString)) catch return ZipponError.MemoryError;
            map.* = std.AutoHashMap([16]u8, JsonString).init(alloc);
            array.append(RelationMap{
                .struct_name = sstruct.links.get(child.name).?,
                .member_name = child.name,
                .additional_data = child.additional_data, // Maybe I need to check if it exist, im not sure it always exist
                .map = map,
            }) catch return ZipponError.MemoryError;
        };
        return array.toOwnedSlice() catch return ZipponError.MemoryError;
    }

    pub fn fileListToParse(
        self: SchemaEngine,
        alloc: Allocator,
        struct_name: []const u8,
        map: std.AutoHashMap([16]u8, JsonString),
    ) ![]usize {
        const sstruct = try self.structName2SchemaStruct(struct_name);
        var unique_indices = std.AutoHashMap(usize, void).init(alloc);

        var iter = map.keyIterator();
        while (iter.next()) |uuid| {
            if (sstruct.uuid_file_index.get(uuid.*)) |file_index| {
                try unique_indices.put(file_index, {});
            }
        }

        var result = try alloc.alloc(usize, unique_indices.count());
        var i: usize = 0;
        var index_iter = unique_indices.keyIterator();
        while (index_iter.next()) |index| {
            result[i] = index.*;
            i += 1;
        }

        return result;
    }
};
