const std = @import("std");
const Allocator = std.mem.Allocator;
const RelationMap = @import("relationMap.zig").RelationMap;
const dtype = @import("dtype");
const DataType = dtype.DataType;

const ZipponError = @import("errors.zig").ZipponError;

/// This is the [] part
pub const AdditionalData = struct {
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
            try self.childrens.append(AdditionalDataMember.init(member, i));
        }
    }

    pub fn addMember(self: *AdditionalData, name: []const u8, index: usize) ZipponError!void {
        self.childrens.append(AdditionalDataMember.init(name, index)) catch return ZipponError.MemoryError;
    }

    pub fn initAdditionalDataOfLastChildren(self: *AdditionalData) *AdditionalData {
        self.childrens.items[self.childrens.items.len - 1].additional_data = AdditionalData.init(self.allocator);
        return &self.childrens.items[self.childrens.items.len - 1].additional_data.?;
    }

    /// Create an array of empty RelationMap based on the additionalData
    pub fn relationMapArrayInit(self: AdditionalData, allocator: Allocator) ZipponError!?[]RelationMap {
    // So here I should have relationship if children are relations
    var array = std.ArrayList(RelationMap).init(allocator);
    for (self.childrens.items) |child| {
        child.
    }
}
};

// This is name in: [name]
// There is an additional data because it can be [friend [1; name]]
pub const AdditionalDataMember = struct {
    name: []const u8,
    index: usize, // Index place in the schema
    additional_data: ?AdditionalData = null,

    pub fn init(name: []const u8, index: usize) AdditionalDataMember {
        return AdditionalDataMember{ .name = name, .index = index };
    }
};
