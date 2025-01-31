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
const ValueOrArray = @import("../ziql/parts/newData.zig").ValueOrArray;
const JsonString = RelationMap.JsonString;

const ZipponError = @import("error").ZipponError;

var empty_map_buf: [20]u8 = undefined;
var fa = std.heap.FixedBufferAllocator.init(&empty_map_buf);
const empty_map_allocator = fa.allocator();

const empty_int: [0]i32 = .{};
const empty_float: [0]f64 = .{};
const empty_unix: [0]u64 = .{};
const empty_bool: [0]bool = .{};
const empty_str: [0][]const u8 = .{};
const zero_link = std.AutoHashMap(UUID, void).init(empty_map_allocator);
const empty_link = std.AutoHashMap(UUID, void).init(empty_map_allocator);

// I need to redo how SchemaStruct work because it is a mess
// I mean I use wayyyyyyyyyyyyyyyyyyyyyyy too much structName2SchemaStruct or stuff like that
// I mean that not good to always for loop and compare when a map would work

pub fn memberName2DataType(self: *Self, struct_name: []const u8, member_name: []const u8) ZipponError!DataType {
    const sstruct = try self.structName2SchemaStruct(struct_name);

    for (sstruct.members, 0..) |mn, i| {
        if (std.mem.eql(u8, mn, member_name)) return sstruct.types[i];
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

// Return the SchemaStruct based on it's name
pub fn structName2SchemaStruct(self: Self, struct_name: []const u8) ZipponError!SchemaStruct {
    var i: usize = 0;

    while (i < self.struct_array.len) : (i += 1) if (std.mem.eql(u8, self.struct_array[i].name, struct_name)) break;

    if (i == self.struct_array.len) {
        return ZipponError.StructNotFound;
    }

    return self.struct_array[i];
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

/// Use with NewData to check if all member are in the map, otherwise write the missing one to be send with the error
/// Also if array and link are missing, to make them empty instead
pub fn checkIfAllMemberInMapAndAddEmptyMissingArray(
    self: Self,
    struct_name: []const u8,
    map: *std.StringHashMap(ValueOrArray),
    writer: std.ArrayList(u8).Writer,
) ZipponError!bool {
    const sstruct = try self.structName2SchemaStruct(struct_name);
    var count: u16 = 0;

    for (sstruct.members, sstruct.types) |mn, dt| {
        if (std.mem.eql(u8, mn, "id")) continue;
        if (map.contains(mn)) count += 1 else {
            if (dt.is_array() or dt == .link) {
                map.put(
                    mn,
                    switch (dt) {
                        .int_array => ValueOrArray{ .value = try ConditionValue.initArrayInt(&empty_int) },
                        .float_array => ValueOrArray{ .value = try ConditionValue.initArrayFloat(&empty_float) },
                        .str_array => ValueOrArray{ .value = try ConditionValue.initArrayStr(&empty_str) },
                        .bool_array => ValueOrArray{ .value = try ConditionValue.initArrayBool(&empty_bool) },
                        .date_array => ValueOrArray{ .value = try ConditionValue.initArrayUnix(&empty_unix) },
                        .time_array => ValueOrArray{ .value = try ConditionValue.initArrayUnix(&empty_unix) },
                        .datetime_array => ValueOrArray{ .value = try ConditionValue.initArrayUnix(&empty_unix) },
                        .link_array => ValueOrArray{ .value = ConditionValue.initArrayLink(&empty_link) },
                        .link => ValueOrArray{ .value = ConditionValue.initLink(&zero_link) },
                        else => unreachable,
                    },
                ) catch return ZipponError.MemoryError;
                count += 1;
            }
            writer.print(" {s},", .{mn}) catch return ZipponError.WriteError;
        }
    }

    return ((count == sstruct.members.len - 1) and (count == map.count()));
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
