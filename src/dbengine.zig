const std = @import("std");
const dtypes = @import("dtypes.zig");
const UUID = @import("uuid.zig").UUID;
const ziqlTokenizer = @import("tokenizers/ziqlTokenizer.zig").Tokenizer;
const ziqlToken = @import("tokenizers/ziqlTokenizer.zig").Token;
const Allocator = std.mem.Allocator;

pub const Error = error{UUIDNotFound};
const stdout = std.io.getStdOut().writer();

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Init the map storage string map that track all array of struct
    var storage = std.StringHashMap(*std.ArrayList(dtypes.Types)).init(allocator);
    defer storage.deinit();

    // Create all array and put them in the main map
    // Use MultiArrayList in the future to save memory maybe ?
    for (dtypes.struct_name_list) |struct_name| {
        var array = std.ArrayList(dtypes.Types).init(allocator);
        try storage.put(struct_name, &array);
    }

    // Add user
    const adrien = dtypes.User.init("Adrien", "adrien@gmail.com");
    try storage.get("User").?.append(dtypes.Types{ .User = &adrien });
    const adrien_get = storage.get("User").?.items[0].User;

    if (std.meta.eql(adrien_get, &adrien)) {
        try stdout.print("adrien == adrien_get\n\n", .{});
    }

    // Add a new user
    // const newUser = try dtypes.User.new(allocator, "Adrien", "adrien@gmail.com");
    // try storage.get("User").?.append(dtypes.Types{ .user = newUser });

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Remove the first argument
    _ = args.next();
    const null_term_query_str = args.next();

    var ziqlToker = ziqlTokenizer.init(null_term_query_str.?);
    const firstToken = ziqlToker.next();
    switch (firstToken.tag) {
        .keyword_grab => {
            try stdout.print("Hello from engine\n", .{});
        },
        .keyword_add => {
            try stdout.print("Not yet implemented.\n", .{});
        },
        .keyword_update => {
            try stdout.print("Not yet implemented.\n", .{});
        },
        .keyword_delete => {
            try stdout.print("Not yet implemented.\n", .{});
        },
        .keyword__describe__ => {
            try stdout.print("{s}", .{dtypes.describe_str});
        },
        else => {
            try stdout.print("Query need to start with a keyword, including: GRAB ADD UPDATE DELETE\n", .{});
        },
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

// Function to add and test:
// - Create one entity
// - Search one entity filtering a list of key/value. Eg: User with name = 'Adrien' and age > 10

test "getById" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var users = std.ArrayList(*dtypes.User).init(allocator);
    try users.append(try dtypes.User.new(allocator, "Adrien", "adrien@gmail.com"));

    const adrien = try getById(users, users.items[0].id);

    try std.testing.expect(UUID.compare(users.items[0].id, adrien.id));
}
