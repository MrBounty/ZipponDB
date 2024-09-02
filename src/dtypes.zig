const std = @import("std");
const UUID = @import("uuid.zig").UUID;

pub const Types = union {
    user: *User,
    message: *Message,
};

pub const User = struct {
    id: UUID,
    name: []const u8,
    email: []const u8,
    messages: std.ArrayList(*Message),

    pub fn new(allocator: std.mem.Allocator, name: []const u8, email: []const u8) !*User {
        const user = try allocator.create(User);
        user.* = .{
            .id = UUID.init(),
            .name = name,
            .email = email,
            .messages = std.ArrayList(*Message).init(allocator),
        };
        return user;
    }
};

pub const Message = struct {
    id: UUID,
    content: []const u8,
    user: *User,

    pub fn new(allocator: std.mem.Allocator, content: []const u8, user: *User) !*Message {
        const message = try allocator.create(Message);
        message.* = .{
            .id = UUID.init(),
            .content = content,
            .user = user,
        };
        try user.*.messages.append(message);
        return message;
    }
};
