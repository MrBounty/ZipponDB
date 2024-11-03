const std = @import("std");
const Allocator = std.mem.Allocator;

/// This is the [] part
/// TODO: Include the part ".friends.comments" in "GRAB User.firends.comments {age > 10}"
pub const AdditionalData = struct {
    entity_count_to_find: usize = 0,
    member_to_find: std.ArrayList(AdditionalDataMember),

    pub fn init(allocator: Allocator) AdditionalData {
        return AdditionalData{ .member_to_find = std.ArrayList(AdditionalDataMember).init(allocator) };
    }

    pub fn deinit(self: *AdditionalData) void {
        for (0..self.member_to_find.items.len) |i| {
            self.member_to_find.items[i].additional_data.deinit();
        }

        self.member_to_find.deinit();
    }

    pub fn populateWithEverything(self: *AdditionalData, allocator: Allocator, members: [][]const u8) !void {
        for (members, 0..) |member, i| {
            try self.member_to_find.append(AdditionalDataMember.init(allocator, member, i));
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
