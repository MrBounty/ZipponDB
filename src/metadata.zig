const std = @import("std");

// Maybe create a struct like StructMetadata for the string list of member and name, ect
pub const struct_name_list: [2][]const u8 = .{
    "User",
    "Message",
};

pub const struct_member_list: [2][]const []const u8 = .{
    &[_][]const u8{ "name", "email", "age", "scores" },
    &[_][]const u8{"content"},
};

/// Get the list of all member name for a struct name
pub fn structName2structMembers(struct_name: []const u8) []const []const u8 {
    var i: u16 = 0;

    while (i < struct_name_list.len) : (i += 1) if (std.mem.eql(u8, struct_name_list[i], struct_name)) break;

    return struct_member_list[i];
}

pub fn isStructNameExists(struct_name: []const u8) bool {
    for (struct_name_list) |sn| if (std.mem.eql(u8, sn, struct_name)) return true;
    return false;
}

pub fn isMemberNameInStruct(struct_name: []const u8, member_name: []const u8) bool {
    for (structName2structMembers(struct_name)) |mn| if (std.mem.eql(u8, mn, member_name)) return true;
    return false;
}
