const std = @import("std");
const Allocator = std.mem.Allocator;
const RelationMap = @import("relationMap.zig").RelationMap;
const dtype = @import("dtype");
const DataType = dtype.DataType;

// TODO: Put this in a data structure directory

const ZipponError = @import("errors.zig").ZipponError;

/// This is the [] part
pub const AdditionalData = @This();

allocator: Allocator,
limit: usize = 0,
childrens: std.ArrayList(AdditionalDataMember),

pub fn init(allocator: Allocator) AdditionalData {
    return AdditionalData{
        .allocator = allocator,
        .childrens = std.ArrayList(AdditionalDataMember).init(allocator),
    };
}

pub fn populateWithEverythingExceptLink(self: *AdditionalData, members: [][]const u8, dtypes: []DataType) !void {
    for (members, dtypes, 0..) |member, dt, i| {
        if (dt == .link or dt == .link_array) continue;
        try self.childrens.append(AdditionalDataMember.init(self.allocator, member, i));
    }
}

pub fn addMember(self: *AdditionalData, name: []const u8, index: usize) ZipponError!void {
    self.childrens.append(AdditionalDataMember.init(self.allocator, name, index)) catch return ZipponError.MemoryError;
}

// This is name in: [name]
// There is an additional data because it can be [friend [1; name]]
pub const AdditionalDataMember = struct {
    name: []const u8,
    index: usize, // Index place in the schema
    additional_data: AdditionalData,

    pub fn init(allocator: Allocator, name: []const u8, index: usize) AdditionalDataMember {
        return AdditionalDataMember{ .name = name, .index = index, .additional_data = AdditionalData.init(allocator) };
    }
};
