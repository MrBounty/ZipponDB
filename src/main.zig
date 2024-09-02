const std = @import("std");
const UUID = @import("uuid.zig").UUID;
const dtypes = @import("dtypes.zig");
const ziqlTokenizer = @import("ziqlTokenizer.zig").Tokenizer;
const ziqlToken = @import("ziqlTokenizer.zig").Token;
const cliTokenizer = @import("cliTokenizer.zig").Tokenizer;
const cliToken = @import("cliTokenizer.zig").Token;
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

    while (true) {
        std.debug.print("> ", .{});
        var line_buf: [1024]u8 = undefined;
        const line = try std.io.getStdIn().reader().readUntilDelimiterOrEof(&line_buf, '\n');
        if (line) |line_str| {
            const null_term_line_str = try allocator.dupeZ(u8, line_str[0..line_str.len]);

            var cliToker = cliTokenizer.init(null_term_line_str);
            const commandToken = cliToker.next();
            switch (commandToken.tag) {
                .keyword_run => {
                    const query_token = cliToker.next();
                    switch (query_token.tag) {
                        .string_literal => {
                            std.debug.print("Running query: {s}\n", .{line_str[query_token.loc.start + 1 .. query_token.loc.end - 1]});
                        },
                        else => {
                            std.debug.print("After command run, need a string of a query, eg: \"GRAB User\"\n", .{});
                            continue;
                        },
                    }
                },
                .keyword_describe => {
                    std.debug.print("Current schema: \n\nUser (\n\tid: UUID,\n\tname; str,\n\temail: str,\n\tmessages: []Message\n)\n\nMessage (\n\tid: UUID,\n\tcontent; str,\n\tfrom: User,\n)\n", .{});
                },
                .keyword_help => {
                    std.debug.print("Welcome to ZipponDB.\n\nrun\t\tTo run a query. Args: query: str, the query to execute.\ndescribe\tTo print the current schema.\nkill\t\tTo stop the process without saving\nsave\t\tSave the database to the normal files.\ndump\t\tCreate a new folder with all data as copy. Args: foldername: str, the name of the folder.\nbump\t\tReplace current data with a previous dump; Note: Save the current state with the dump command. Args: foldername: str, the name of the folder to use.\n", .{});
                },
                .keyword_quit => {
                    break;
                },
                else => {
                    std.debug.print("Command need to start with a keyword, including: run, describe, help and quit\n", .{});
                },
            }
        }
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

fn startsWithDoubleQuote(s: []const u8) bool {
    if (s.len < 2) return false;
    return s[0] == '"' and s[s.len - 1] == '"';
}

fn endsWithDoubleQuote(s: []const u8) bool {
    if (s.len < 2) return false;
    return s[s.len - 1] == '"';
}

test "getById" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var users = std.ArrayList(*dtypes.User).init(allocator);
    try users.append(try dtypes.User.new(allocator, "Adrien", "adrien@gmail.com"));

    const adrien = try getById(users, users.items[0].id);

    try std.testing.expect(UUID.compare(users.items[0].id, adrien.id));
}
