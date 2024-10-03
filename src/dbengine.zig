const std = @import("std");
const DataEngine = @import("dataEngine.zig").DataEngine;
const Tokenizer = @import("ziqlTokenizer.zig").Tokenizer;
const grabParser = @import("GRAB.zig").Parser;
const addParser = @import("ADD.zig").Parser;

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

    switch (first_token.tag) {
        .keyword_grab => {
            var parser = grabParser.init(allocator, &toker);
            try parser.parse();
        },
        .keyword_add => {
            var parser = addParser.init(allocator, &toker);
            parser.parse() catch |err| {
                try stdout.print("Error: {any} while parsin ADD.\n", .{err});
            };
        },
        .keyword_update => {
            try stdout.print("Not yet implemented.\n", .{});
        },
        .keyword_delete => {
            try stdout.print("Not yet implemented.\n", .{});
        },
        .keyword__describe__ => {
            try stdout.print("{s}", .{@embedFile("schema.zipponschema")});
        },
        .keyword__init__ => {
            var data_engine = DataEngine.init(allocator, null);
            try data_engine.initDataFolder();
        },
        else => {
            try stdout.print("Query need to start with a keyword, including: GRAB ADD UPDATE DELETE\n", .{});
        },
    }
}
