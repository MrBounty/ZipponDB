const std = @import("std");
const Allocator = std.mem.Allocator;
const dtype = @import("dtype");
const DataType = dtype.DataType;

/// This is the [] part
/// TODO: Include the part ".friends.comments" in "GRAB User.firends.comments {age > 10}"
pub const AdditionalData = struct {
    limit: usize = 0,
    childrens: std.ArrayList(AdditionalDataMember),

    pub fn init(allocator: Allocator) AdditionalData {
        return AdditionalData{ .childrens = std.ArrayList(AdditionalDataMember).init(allocator) };
    }

    pub fn deinit(self: *AdditionalData) void {
        for (0..self.childrens.items.len) |i| {
            self.childrens.items[i].additional_data.deinit();
        }

        self.childrens.deinit();
    }

    pub fn populateWithEverythingExceptLink(self: *AdditionalData, allocator: Allocator, members: [][]const u8, dtypes: []DataType) !void {
        for (members, dtypes, 0..) |member, dt, i| {
            if (dt == .link or dt == .link_array) continue;
            try self.childrens.append(AdditionalDataMember.init(allocator, member, i));
        }
    }
};

// This is name in: [name]
// There is an additional data because it can be [friend [1; name]]
pub const AdditionalDataMember = struct {
    name: []const u8,
    index: usize, // Index place in the schema
    additional_data: AdditionalData,

    pub fn init(allocator: Allocator, name: []const u8, index: usize) AdditionalDataMember {
        const additional_data = AdditionalData.init(allocator);
        return AdditionalDataMember{ .name = name, .additional_data = additional_data, .index = index };
    }
};
