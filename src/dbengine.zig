const std = @import("std");
const dtypes = @import("dtypes.zig");
const UUID = @import("uuid.zig").UUID;
const ziqlTokenizer = @import("tokenizers/ziqlTokenizer.zig").Tokenizer;
const ziqlToken = @import("tokenizers/ziqlTokenizer.zig").Token;
const grabParser = @import("query_functions/GRAB.zig").Parser;
const Allocator = std.mem.Allocator;
const parseDataAndAddToFile = @import("query_functions/ADD.zig").parseDataAndAddToFile;

pub const Error = error{UUIDNotFound};
const stdout = std.io.getStdOut().writer();

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const buffer = try allocator.alloc(u8, 1024);
    defer allocator.free(buffer);

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
    //const adrien = dtypes.User.init("Adrien", "adrien@gmail.com");
    //try storage.get("User").?.append(dtypes.Types{ .User = &adrien });
    //const adrien_get = storage.get("User").?.items[0].User;

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Remove the first argument
    _ = args.next();
    const null_term_query_str = args.next().?;

    var ziqlToker = ziqlTokenizer.init(null_term_query_str);
    const first_token = ziqlToker.next();
    const struct_name_token = ziqlToker.next();

    switch (first_token.tag) {
        .keyword_grab => {
            var parser = grabParser.init(&ziqlToker);
            try parser.parse_additional_data();
        },
        .keyword_add => {
            if (!isStructInSchema(ziqlToker.getTokenSlice(struct_name_token))) {
                try stdout.print("Error: No struct named '{s}' in current schema.", .{ziqlToker.getTokenSlice(struct_name_token)});
                return;
            }
            try parseDataAndAddToFile(allocator, ziqlToker.getTokenSlice(struct_name_token), &ziqlToker);
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

/// Check if a string is a name of a struct in the currently use engine
fn isStructInSchema(struct_name_to_check: []const u8) bool {
    if (std.mem.eql(u8, struct_name_to_check, "describe")) return true;

    for (dtypes.struct_name_list) |struct_name| {
        if (std.mem.eql(u8, struct_name_to_check, struct_name)) {
            return true;
        }
    }
    return false;
}
