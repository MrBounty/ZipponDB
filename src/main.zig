const std = @import("std");
const UUID = @import("uuid.zig").UUID;
const dtypes = @import("dtypes.zig");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Token = @import("tokenizer.zig").Token;
const Allocator = std.mem.Allocator;
const print = std.debug.print;

pub const Error = error{UUIDNotFound};

const Commands = enum { run, describe, help, unknow, @"run describe help unknow" };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Init the map storage string map that track all array of struct
    var storage = std.StringHashMap(*std.ArrayList(dtypes.Types)).init(allocator);
    defer storage.deinit();

    // Create all array and put them in the main map
    var userArray = std.ArrayList(dtypes.Types).init(allocator);
    try storage.put("User", &userArray);

    var postArray = std.ArrayList(dtypes.Types).init(allocator);
    try storage.put("Post", &postArray);

    var commentArray = std.ArrayList(dtypes.Types).init(allocator);
    try storage.put("Comment", &commentArray);

    // Add a new user
    const newUser = try dtypes.User.new(allocator, "Adrien", "adrien@gmail.com");
    try storage.get("User").?.append(dtypes.Types{ .user = newUser });

    std.debug.print("{s}\n", .{storage.get("User").?.items[0].user.email});

    // Lets get arguments and what the user want to do
    var argsIterator = try std.process.ArgIterator.initWithAllocator(allocator);
    defer argsIterator.deinit();

    // Skip executable
    _ = argsIterator.next();

    if (argsIterator.next()) |commandStr| {
        const command = std.meta.stringToEnum(Commands, commandStr) orelse Commands.unknow;
        switch (command) {
            .run => {
                const query = argsIterator.next();
                var tokenizer = Tokenizer.init(query.?);
                var token = tokenizer.next();
                while (token.tag != Token.Tag.eof) {
                    std.debug.print("{any}\n", .{token});
                    token = tokenizer.next();
                }
            },
            .help => {
                std.debug.print("Welcome to ZipponDB!.", .{});
            },
            .describe => {
                std.debug.print("Here the current schema:\nUser (\n\tname: str,\n\temail:str,\n\tfriend:User\n)\n", .{});
            },
            .unknow => {
                std.debug.print("Unknow command, available are: run, describe, help.\n", .{});
            },
            else => {},
        }
    } else {
        std.debug.print("No args found. Available are: run, help.\n", .{});
    }
}

fn getById(array: anytype, id: UUID) !*dtypes.User {
    for (array.items) |data| {
        if (data.id.compare(id)) {
            return data;
        }
    }
    return error.UUIDNotFound;
}

test "getById" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var users = std.ArrayList(*dtypes.User).init(allocator);
    try users.append(try dtypes.User.new(allocator, "Adrien", "adrien@gmail.com"));

    const adrien = try getById(users, users.items[0].id);

    try std.testing.expect(UUID.compare(users.items[0].id, adrien.id));
}
