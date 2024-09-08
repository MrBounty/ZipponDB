const std = @import("std");
const UUID = @import("uuid.zig").UUID;

pub const parameter_max_file_size = 1e+7; // THe number of bytes than each file can be before splitting

pub const User = struct {
    id: UUID,
    name: []const u8,
    email: []const u8,

    pub fn init(name: []const u8, email: []const u8) User {
        return User{ .id = UUID.init(), .name = name, .email = email };
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

pub const struct_name_list: [2][]const u8 = .{
    "User",
    "Message",
};

pub const struct_member_list: [2][][]const u8 = .{
    .{ "name", "email" },
    .{"content"},
};

pub const describe_str = "User (\n  name: str,\n  email: str,\n)\n\nMessage (\n  content: str,\n)\n";
