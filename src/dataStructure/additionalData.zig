const std = @import("std");
const Allocator = std.mem.Allocator;
const RelationMap = @import("relationMap.zig").RelationMap;
const dtype = @import("dtype");
const DataType = dtype.DataType;

const ZipponError = @import("error").ZipponError;

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

pub fn populateWithEverythingExceptLink(self: *AdditionalData, members: [][]const u8, dtypes: []DataType) ZipponError!void {
    for (members, dtypes, 0..) |member, dt, i| {
        if (dt == .link or dt == .link_array) continue;
        self.childrens.append(AdditionalDataMember.init(self.allocator, member, i)) catch return ZipponError.MemoryError;
    }
}

pub fn addMember(self: *AdditionalData, name: []const u8, index: usize) ZipponError!void {
    self.childrens.append(AdditionalDataMember.init(self.allocator, name, index)) catch return ZipponError.MemoryError;
}

pub fn clone(self: AdditionalData, allocator: Allocator) ZipponError!AdditionalData {
    var new_additional_data = AdditionalData.init(allocator);

    new_additional_data.limit = self.limit;

    for (self.childrens.items) |child| {
        new_additional_data.childrens.append(child.clone(allocator) catch return ZipponError.MemoryError) catch return ZipponError.MemoryError;
    }

    return new_additional_data;
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

    pub fn clone(self: AdditionalDataMember, allocator: Allocator) ZipponError!AdditionalDataMember {
        return AdditionalDataMember{
            .name = allocator.dupe(u8, self.name) catch return ZipponError.MemoryError,
            .index = self.index,
            .additional_data = self.additional_data.clone(allocator) catch return ZipponError.MemoryError,
        };
    }
};
