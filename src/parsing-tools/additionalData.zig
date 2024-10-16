const std = @import("std");
const Allocator = std.mem.Allocator;

/// This is the [] part
/// IDK if saving it into the Parser struct is a good idea
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

    pub fn contains(additional_data: AdditionalData, member_name: []const u8) bool {
        for (additional_data.member_to_find.items) |elem| {
            if (std.mem.eql(u8, member_name, elem.name)) return true;
        }
        return false;
    }
};

// This is name in: [name]
// There is an additional data because it can be [friend [1; name]]
pub const AdditionalDataMember = struct {
    name: []const u8,
    additional_data: AdditionalData,

    pub fn init(allocator: Allocator, name: []const u8) AdditionalDataMember {
        const additional_data = AdditionalData.init(allocator);
        return AdditionalDataMember{ .name = name, .additional_data = additional_data };
    }
};
