const std = @import("std");
const dtypes = @import("dtypes.zig");
const UUID = @import("uuid.zig").UUID;
const Tokenizer = @import("ziqlTokenizer.zig").Tokenizer;
const Token = @import("ziqlTokenizer.zig").Token;
const grabParser = @import("GRAB.zig").Parser;
const addParser = @import("ADD.zig").Parser;
const DataEngine = @import("dataEngine.zig").DataEngine;
const Allocator = std.mem.Allocator;

pub const Error = error{UUIDNotFound};
const stdout = std.io.getStdOut().writer();

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const buffer = try allocator.alloc(u8, 1024);
    defer allocator.free(buffer);

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Remove the first argument
    _ = args.next();
    const null_term_query_str = args.next().?;

    var toker = Tokenizer.init(null_term_query_str);
    const first_token = toker.next();
    const struct_name_token = toker.next();

    var data_engine = DataEngine.init(allocator);

    switch (first_token.tag) {
        .keyword_grab => {
            if (!isStructInSchema(toker.getTokenSlice(struct_name_token))) {
                try stdout.print("Error: No struct named '{s}' in current schema.", .{toker.getTokenSlice(struct_name_token)});
                return;
            }
            var parser = grabParser.init(allocator, &toker, &data_engine);
            try parser.parse();
        },
        .keyword_add => {
            if (!isStructInSchema(toker.getTokenSlice(struct_name_token))) {
                try stdout.print("Error: No struct named '{s}' in current schema.", .{toker.getTokenSlice(struct_name_token)});
                return;
            }
            var parser = addParser.init(allocator, &toker, &data_engine);
            try parser.parse(toker.getTokenSlice(struct_name_token));
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
