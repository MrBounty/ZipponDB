pub const Self = @import("core.zig");
const std = @import("std");
const dtype = @import("dtype");
const Allocator = std.mem.Allocator;
const UUID = dtype.UUID;
const DataType = dtype.DataType;
const SchemaStruct = @import("struct.zig");
const ConditionValue = @import("../dataStructure/filter.zig").ConditionValue;
const AdditionalData = @import("../dataStructure/additionalData.zig");
const RelationMap = @import("../dataStructure/relationMap.zig");
const JsonString = RelationMap.JsonString;

const ZipponError = @import("error").ZipponError;

// I need to redo how SchemaStruct work because it is a mess
// I mean I use wayyyyyyyyyyyyyyyyyyyyyyy too much structName2SchemaStruct or stuff like that
// I mean that not good to always for loop and compare when a map would work

pub fn memberName2DataType(self: *Self, struct_name: []const u8, member_name: []const u8) ZipponError!DataType {
    for (try self.structName2structMembers(struct_name), 0..) |mn, i| {
        const dtypes = try self.structName2DataType(struct_name);
        if (std.mem.eql(u8, mn, member_name)) return dtypes[i];
    }

    return ZipponError.MemberNotFound;
}

pub fn memberName2DataIndex(self: *Self, struct_name: []const u8, member_name: []const u8) ZipponError!usize {
    for (try self.structName2structMembers(struct_name), 0..) |mn, i| {
        if (std.mem.eql(u8, mn, member_name)) return i;
    }

    return ZipponError.MemberNotFound;
}

/// Get the list of all member name for a struct name
pub fn structName2structMembers(self: Self, struct_name: []const u8) ZipponError![][]const u8 {
    var i: usize = 0;

    while (i < self.struct_array.len) : (i += 1) if (std.mem.eql(u8, self.struct_array[i].name, struct_name)) break;

    if (i == self.struct_array.len) {
        return ZipponError.StructNotFound;
    }

    return self.struct_array[i].members;
}

// TODO: This is the first one I want to change to use a map
pub fn structName2SchemaStruct(self: Self, struct_name: []const u8) ZipponError!SchemaStruct {
    var i: usize = 0;

    while (i < self.struct_array.len) : (i += 1) if (std.mem.eql(u8, self.struct_array[i].name, struct_name)) break;

    if (i == self.struct_array.len) {
        return ZipponError.StructNotFound;
    }

    return self.struct_array[i];
}

pub fn structName2DataType(self: Self, struct_name: []const u8) ZipponError![]const DataType {
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
pub fn isStructNameExists(self: Self, struct_name: []const u8) bool {
    var i: u16 = 0;
    while (i < self.struct_array.len) : (i += 1) if (std.mem.eql(u8, self.struct_array[i].name, struct_name)) return true;
    return false;
}

/// Check if a struct have the member name
pub fn isMemberNameInStruct(self: Self, struct_name: []const u8, member_name: []const u8) ZipponError!bool {
    for (try self.structName2structMembers(struct_name)) |mn| {
        if (std.mem.eql(u8, mn, member_name)) return true;
    }
    return false;
}

/// Return the SchemaStruct of the struct that the member is linked. So if it is not a link, it is itself, if it is a link, it the the sstruct of the link
pub fn linkedStructName(self: Self, struct_name: []const u8, member_name: []const u8) ZipponError!SchemaStruct {
    const sstruct = try self.structName2SchemaStruct(struct_name);
    if (sstruct.links.get(member_name)) |struct_link_name| {
        return try self.structName2SchemaStruct(struct_link_name);
    }
    return sstruct;
}

pub fn checkIfAllMemberInMap(
    self: Self,
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

pub fn isUUIDExist(self: Self, struct_name: []const u8, uuid: UUID) bool {
    const sstruct = self.structName2SchemaStruct(struct_name) catch return false;
    return sstruct.uuid_file_index.contains(uuid);
}

/// Create an array of empty RelationMap based on the additionalData
pub fn relationMapArrayInit(
    self: Self,
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
    self: Self,
    alloc: Allocator,
    struct_name: []const u8,
    map: std.AutoHashMap([16]u8, JsonString),
) ZipponError![]usize {
    const sstruct = try self.structName2SchemaStruct(struct_name);
    var unique_indices = std.AutoHashMap(usize, void).init(alloc);
    defer unique_indices.deinit();

    var iter = map.keyIterator();
    while (iter.next()) |uuid| {
        if (sstruct.uuid_file_index.get(UUID{ .bytes = uuid.* })) |file_index| {
            unique_indices.put(file_index, {}) catch return ZipponError.MemoryError;
        }
    }

    var result = alloc.alloc(usize, unique_indices.count()) catch return ZipponError.MemoryError;
    var i: usize = 0;
    var index_iter = unique_indices.keyIterator();
    while (index_iter.next()) |index| {
        result[i] = index.*;
        i += 1;
    }

    return result;
}
