const std = @import("std");
const dtype = @import("dtype");
const zid = @import("ZipponData");
const Allocator = std.mem.Allocator;
const DataType = dtype.DataType;
const UUIDFileIndex = @import("../dataStructure/UUIDFileIndex.zig");

const ZipponError = @import("error").ZipponError;

/// Represent one struct in the schema
pub const Self = @This();

name: []const u8,
members: [][]const u8,
types: []DataType,
zid_schema: []zid.DType,
links: std.StringHashMap([]const u8), // Map key as member_name and value as struct_name of the link
uuid_file_index: *UUIDFileIndex, // Map UUID to the index of the file store in

pub fn init(
    allocator: Allocator,
    name: []const u8,
    members: [][]const u8,
    types: []DataType,
    links: std.StringHashMap([]const u8),
) ZipponError!Self {
    const uuid_file_index = allocator.create(UUIDFileIndex) catch return ZipponError.MemoryError;
    uuid_file_index.* = UUIDFileIndex.init(allocator) catch return ZipponError.MemoryError;
    return Self{
        .name = name,
        .members = members,
        .types = types,
        .zid_schema = Self.fileDataSchema(allocator, types) catch return ZipponError.MemoryError,
        .links = links,
        .uuid_file_index = uuid_file_index,
    };
}

fn fileDataSchema(allocator: Allocator, dtypes: []DataType) ZipponError![]zid.DType {
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
