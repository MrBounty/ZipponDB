const std = @import("std");
const dtypes = @import("dtypes.zig");
const UUID = @import("uuid.zig").UUID;
const ziqlTokenizer = @import("tokenizers/ziqlTokenizer.zig").Tokenizer;
const ziqlToken = @import("tokenizers/ziqlTokenizer.zig").Token;

// Test for functions in for_add.zig
const getMapOfMember = @import("query_functions/ADD.zig").getMapOfMember;

test "Get map of members" {
    const allocator = std.testing.allocator;

    const in = "(name='Adrien', email='adrien@gmail.com', age=26, scores=[42 100 5])";
    const null_term_in = try allocator.dupeZ(u8, in);

    var toker = ziqlTokenizer.init(null_term_in);

    const member_map = try getMapOfMember(allocator, &toker);
    std.debug.print("{s}", .{member_map.get("name").?});

    allocator.free(null_term_in);
}
