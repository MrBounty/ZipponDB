const std = @import("std");
const UUID = @import("uuid.zig").UUID;

pub const User = struct {
    id: UUID,
    name: []u8,
    email: []u8,

    pub fn init(id: UUID, name: []const u8, email: []const u8) User {
        return User{ .id = id, .name = name, .email = email };
    }
};

pub const Message = struct {
    id: UUID,
    content: []u8,

    pub fn init(id: UUID, content: []const u8) Message {
        return Message{ .id = id, .content = content };
    }
};

pub const Types = union {
    User: *User,
    Message: *Message,
};

pub const struct_name_list: [2][]const u8 = .{
    "User",
    "Message",
};

pub const describe_str = "User (\n  name: str,\n  email: str,\n)\n\nMessage (\n  content: str,\n)\n";
