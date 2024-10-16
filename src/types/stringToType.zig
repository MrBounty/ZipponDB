const std = @import("std");
const UUID = @import("uuid.zig").UUID;

// TODO: Put those functions somewhere else
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

pub fn parseFloat(value_str: []const u8) f64 {
    return std.fmt.parseFloat(f64, value_str) catch return 0;
}

pub fn parseArrayFloat(allocator: std.mem.Allocator, array_str: []const u8) std.ArrayList(f64) {
    var array = std.ArrayList(f64).init(allocator);

    var it = std.mem.splitAny(u8, array_str[1 .. array_str.len - 1], " ");
    while (it.next()) |x| {
        array.append(parseFloat(x)) catch {};
    }

    return array;
}

pub fn parseBool(value_str: []const u8) bool {
    return (value_str[0] != '0');
}

pub fn parseArrayBool(allocator: std.mem.Allocator, array_str: []const u8) std.ArrayList(bool) {
    var array = std.ArrayList(bool).init(allocator);

    var it = std.mem.splitAny(u8, array_str[1 .. array_str.len - 1], " ");
    while (it.next()) |x| {
        array.append(parseBool(x)) catch {};
    }

    return array;
}

pub fn parseArrayUUID(allocator: std.mem.Allocator, array_str: []const u8) std.ArrayList(UUID) {
    var array = std.ArrayList(UUID).init(allocator);

    var it = std.mem.splitAny(u8, array_str[1 .. array_str.len - 1], " ");
    while (it.next()) |x| {
        const uuid = UUID.parse(x) catch continue;
        array.append(uuid) catch continue;
    }

    return array;
}

// FIXME: I think it will not work if there is a ' inside the string
pub fn parseArrayStr(allocator: std.mem.Allocator, array_str: []const u8) std.ArrayList([]const u8) {
    var array = std.ArrayList([]const u8).init(allocator);

    var it = std.mem.splitAny(u8, array_str[1 .. array_str.len - 1], "'");
    while (it.next()) |x| {
        if (std.mem.eql(u8, " ", x)) continue;
        const x_copy = allocator.dupe(u8, x) catch @panic("=(");
        // FIXME: I think I need to add the '' on each side again
        array.append(x_copy) catch {};
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

    // Int array
    const in2 = "[1 14 44 42 hello]";
    const out2 = parseArrayInt(allocator, in2);
    defer out2.deinit();
    const expected_out2: [5]i64 = .{ 1, 14, 44, 42, 0 };
    try std.testing.expect(std.mem.eql(i64, out2.items, &expected_out2));

    // Float
    const in3: [3][]const u8 = .{ "1.3", "65.991", "Hello" };
    const expected_out3: [3]f64 = .{ 1.3, 65.991, 0 };
    for (in3, 0..) |value, i| {
        try std.testing.expect(parseFloat(value) == expected_out3[i]);
    }

    // Float array
    const in4 = "[1.5 14.3 44.9999 42 hello]";
    const out4 = parseArrayFloat(allocator, in4);
    defer out4.deinit();
    const expected_out4: [5]f64 = .{ 1.5, 14.3, 44.9999, 42, 0 };
    try std.testing.expect(std.mem.eql(f64, out4.items, &expected_out4));

    // Bool
    const in5: [3][]const u8 = .{ "1", "Hello", "0" };
    const expected_out5: [3]bool = .{ true, true, false };
    for (in5, 0..) |value, i| {
        try std.testing.expect(parseBool(value) == expected_out5[i]);
    }

    // Bool array
    const in6 = "[1 0 0 1 1]";
    const out6 = parseArrayBool(allocator, in6);
    defer out6.deinit();
    const expected_out6: [5]bool = .{ true, false, false, true, true };
    try std.testing.expect(std.mem.eql(bool, out6.items, &expected_out6));

    // TODO: Test the string array
}
