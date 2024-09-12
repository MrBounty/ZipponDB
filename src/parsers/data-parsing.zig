const std = @import("std");

// Series of functions to use just before creating an entity.
// Will transform the string of data into data of the right type.

pub fn parseInt(value_str: []const u8) i64 {
    return std.fmt.parseInt(i64, value_str, 10) catch return 0;
}

pub fn parseArrayInt(allocator: std.mem.Allocator, array_str: []const u8) std.ArrayList(i64) {
    var array = std.ArrayList(i64).init(allocator);

    var it = std.mem.splitAny(u8, array_str[1 .. array_str.len - 1], " ");
    while (it.next()) |x| {
        array.append(parseInt(x)) catch {};
    }

    return array;
}

test "Data parsing" {
    const allocator = std.testing.allocator;

    // Int
    const in1: [3][]const u8 = .{ "1", "42", "Hello" };
    const expected_out1: [3]i64 = .{ 1, 42, 0 };
    for (in1, 0..) |value, i| {
        try std.testing.expect(parseInt(value) == expected_out1[i]);
    }
    std.debug.print("OK\tData parsing: Int\n", .{});

    // Int array
    const in2 = "[1 14 44 42 hello]";
    const out2 = parseArrayInt(allocator, in2);
    defer out2.deinit();
    const expected_out2: [5]i64 = .{ 1, 14, 44, 42, 0 };
    try std.testing.expect(std.mem.eql(i64, out2.items, &expected_out2));
    std.debug.print("OK\tData parsing: Int array\n", .{});
}
