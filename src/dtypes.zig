const std = @import("std");
const UUID = @import("uuid.zig").UUID;
const dataParsing = @import("data-parsing.zig");

pub const parameter_max_file_size_in_bytes = 500; // THe number of bytes than each file can be before splitting

pub const User = struct {
    id: UUID,
    name: []const u8,
    email: []const u8,
    age: i64,
    scores: []i64,

    pub fn init(name: []const u8, email: []const u8, age: i64, scores: []i64) User {
        return User{ .id = UUID.init(), .name = name, .email = email, .age = age, .scores = scores };
    }
};

pub const Message = struct {
    id: UUID,
    content: []const u8,

    pub fn init(content: []const u8) Message {
        return Message{ .id = UUID.init(), .content = content };
    }
};

pub const Types = union {
    User: *const User,
    Message: *const Message,
};

// Maybe create a struct like StructMetadata for the string list of member and name, ect
pub const struct_name_list: [2][]const u8 = .{
    "User",
    "Message",
};

pub const struct_member_list: [2][]const []const u8 = .{
    &[_][]const u8{ "name", "email", "age", "scores" },
    &[_][]const u8{"content"},
};

// For now there is 4 types of data: str, int, float, bool
const MemberTypes = enum { int, float, bool, str };

pub const describe_str = "User (\n  name: str,\n  email: str,\n)\n\nMessage (\n  content: str,\n)\n";

/// User a map of member name / value string to create a new entity of a type
/// The goal being an array of map while parsing files to then return an array of entities and do some fileting on it.
pub fn createEntityFromMap(allocator: std.mem.Allocator, struct_name: []const u8, map: std.StringHashMap([]const u8)) !*Types {
    var t = try allocator.create(Types);
    if (std.mem.eql(u8, struct_name, "User")) {
        const age = try std.fmt.parseInt(i64, map.get("age").?, 10);
        const scores = dataParsing.parseArrayInt(allocator, map.get("scores").?);
        t.User = &User.init(map.get("name").?, map.get("email").?, age, scores.items);
    } else {
        return error.UnknowStructName;
    }
    return t;
}

/// Get the list of all member name for a struct name
pub fn structName2structMembers(struct_name: []const u8) []const []const u8 {
    var i: u16 = 0;

    while (i < struct_name_list.len) : (i += 1) {
        if (std.mem.eql(u8, struct_name_list[i], struct_name)) break;
    }

    return struct_member_list[i];
}
