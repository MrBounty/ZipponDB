const std = @import("std");
const UUID = @import("uuid.zig").UUID;
const DateTime = @import("date.zig").DateTime;

// FIXME: Stop returning arrayList and use toOwnedSlice instead

// TODO: Put those functions somewhere else
pub fn parseInt(value_str: []const u8) i32 {
    return std.fmt.parseInt(i32, value_str, 10) catch return 0;
}

pub fn parseArrayInt(allocator: std.mem.Allocator, array_str: []const u8) ![]const i32 {
    var array = std.ArrayList(i32).init(allocator);

    var it = std.mem.splitAny(u8, array_str[1 .. array_str.len - 1], " ");
    while (it.next()) |x| {
        try array.append(parseInt(x));
    }

    return try array.toOwnedSlice();
}

pub fn parseFloat(value_str: []const u8) f64 {
    return std.fmt.parseFloat(f64, value_str) catch return 0;
}

pub fn parseArrayFloat(allocator: std.mem.Allocator, array_str: []const u8) ![]const f64 {
    var array = std.ArrayList(f64).init(allocator);

    var it = std.mem.splitAny(u8, array_str[1 .. array_str.len - 1], " ");
    while (it.next()) |x| {
        try array.append(parseFloat(x));
    }

    return try array.toOwnedSlice();
}

pub fn parseBool(value_str: []const u8) bool {
    return (value_str[0] != '0');
}

pub fn parseDate(value_str: []const u8) DateTime {
    const year: u16 = std.fmt.parseInt(u16, value_str[0..4], 10) catch 0;
    const month: u16 = std.fmt.parseInt(u16, value_str[5..7], 10) catch 0;
    const day: u16 = std.fmt.parseInt(u16, value_str[8..10], 10) catch 0;

    return DateTime.init(year, month, day, 0, 0, 0, 0);
}

pub fn parseArrayDate(allocator: std.mem.Allocator, array_str: []const u8) ![]const DateTime {
    var array = std.ArrayList(DateTime).init(allocator);

    var it = std.mem.splitAny(u8, array_str[1 .. array_str.len - 1], " ");
    while (it.next()) |x| {
        try array.append(parseDate(x));
    }

    return try array.toOwnedSlice();
}

pub fn parseArrayDateUnix(allocator: std.mem.Allocator, array_str: []const u8) ![]const u64 {
    var array = std.ArrayList(u64).init(allocator);

    var it = std.mem.splitAny(u8, array_str[1 .. array_str.len - 1], " ");
    while (it.next()) |x| {
        try array.append(parseDate(x).toUnix());
    }

    return array.toOwnedSlice();
}

pub fn parseTime(value_str: []const u8) DateTime {
    const hours: u16 = std.fmt.parseInt(u16, value_str[0..2], 10) catch 0;
    const minutes: u16 = std.fmt.parseInt(u16, value_str[3..5], 10) catch 0;
    const seconds: u16 = if (value_str.len > 6) std.fmt.parseInt(u16, value_str[6..8], 10) catch 0 else 0;
    const milliseconds: u16 = if (value_str.len > 9) std.fmt.parseInt(u16, value_str[9..13], 10) catch 0 else 0;

    return DateTime.init(0, 0, 0, hours, minutes, seconds, milliseconds);
}

pub fn parseArrayTime(allocator: std.mem.Allocator, array_str: []const u8) ![]const DateTime {
    var array = std.ArrayList(DateTime).init(allocator);

    var it = std.mem.splitAny(u8, array_str[1 .. array_str.len - 1], " ");
    while (it.next()) |x| {
        try array.append(parseTime(x));
    }

    return try array.toOwnedSlice();
}

pub fn parseArrayTimeUnix(allocator: std.mem.Allocator, array_str: []const u8) ![]const u64 {
    var array = std.ArrayList(u64).init(allocator);

    var it = std.mem.splitAny(u8, array_str[1 .. array_str.len - 1], " ");
    while (it.next()) |x| {
        try array.append(parseTime(x).toUnix());
    }

    return try array.toOwnedSlice();
}

pub fn parseDatetime(value_str: []const u8) DateTime {
    const year: u16 = std.fmt.parseInt(u16, value_str[0..4], 10) catch 0;
    const month: u16 = std.fmt.parseInt(u16, value_str[5..7], 10) catch 0;
    const day: u16 = std.fmt.parseInt(u16, value_str[8..10], 10) catch 0;
    const hours: u16 = std.fmt.parseInt(u16, value_str[11..13], 10) catch 0;
    const minutes: u16 = std.fmt.parseInt(u16, value_str[14..16], 10) catch 0;
    const seconds: u16 = if (value_str.len > 17) std.fmt.parseInt(u16, value_str[17..19], 10) catch 0 else 0;
    const milliseconds: u16 = if (value_str.len > 20) std.fmt.parseInt(u16, value_str[20..24], 10) catch 0 else 0;

    return DateTime.init(year, month, day, hours, minutes, seconds, milliseconds);
}

pub fn parseArrayDatetime(allocator: std.mem.Allocator, array_str: []const u8) ![]const DateTime {
    var array = std.ArrayList(DateTime).init(allocator);

    var it = std.mem.splitAny(u8, array_str[1 .. array_str.len - 1], " ");
    while (it.next()) |x| {
        try array.append(parseDatetime(x));
    }

    return try array.toOwnedSlice();
}

pub fn parseArrayDatetimeUnix(allocator: std.mem.Allocator, array_str: []const u8) ![]const u64 {
    var array = std.ArrayList(u64).init(allocator);

    var it = std.mem.splitAny(u8, array_str[1 .. array_str.len - 1], " ");
    while (it.next()) |x| {
        try array.append(parseDatetime(x).toUnix());
    }

    return try array.toOwnedSlice();
}

pub fn parseArrayBool(allocator: std.mem.Allocator, array_str: []const u8) ![]const bool {
    var array = std.ArrayList(bool).init(allocator);

    var it = std.mem.splitAny(u8, array_str[1 .. array_str.len - 1], " ");
    while (it.next()) |x| {
        try array.append(parseBool(x));
    }

    return try array.toOwnedSlice();
}

pub fn parseArrayUUID(allocator: std.mem.Allocator, array_str: []const u8) ![]const UUID {
    var array = std.ArrayList(UUID).init(allocator);

    var it = std.mem.splitAny(u8, array_str[1 .. array_str.len - 1], " ");
    while (it.next()) |x| {
        const uuid = try UUID.parse(x);
        try array.append(uuid);
    }

    return try array.toOwnedSlice();
}

pub fn parseArrayUUIDBytes(allocator: std.mem.Allocator, array_str: []const u8) ![]const [16]u8 {
    var array = std.ArrayList([16]u8).init(allocator);

    var it = std.mem.splitAny(u8, array_str[1 .. array_str.len - 1], " ");
    while (it.next()) |x| {
        const uuid = try UUID.parse(x);
        try array.append(uuid.bytes);
    }

    return try array.toOwnedSlice();
}

// FIXME: I think it will not work if there is a ' inside the string, even \', need to fix that
pub fn parseArrayStr(allocator: std.mem.Allocator, array_str: []const u8) ![]const []const u8 {
    var array = std.ArrayList([]const u8).init(allocator);

    var it = std.mem.splitAny(u8, array_str[1 .. array_str.len - 1], "'");
    _ = it.next(); // SSkip first token that is empty
    while (it.next()) |x| {
        if (std.mem.eql(u8, " ", x)) continue;
        try array.append(x);
    }

    if (array.items.len > 0) allocator.free(array.pop()); // Remove the last because empty like the first one

    return try array.toOwnedSlice();
}

test "Value parsing: Int" {
    const allocator = std.testing.allocator;

    // Int
    const values: [3][]const u8 = .{ "1", "42", "Hello" };
    const expected_values: [3]i32 = .{ 1, 42, 0 };
    for (values, 0..) |value, i| {
        try std.testing.expect(parseInt(value) == expected_values[i]);
    }

    // Int array
    const array_str = "[1 14 44 42 hello]";
    const array = try parseArrayInt(allocator, array_str);
    defer allocator.free(array);
    const expected_array: [5]i32 = .{ 1, 14, 44, 42, 0 };
    try std.testing.expect(std.mem.eql(i32, array, &expected_array));
}

test "Value parsing: Float" {
    const allocator = std.testing.allocator;
    // Float
    const values: [3][]const u8 = .{ "1.3", "65.991", "Hello" };
    const expected_values: [3]f64 = .{ 1.3, 65.991, 0 };
    for (values, 0..) |value, i| {
        try std.testing.expect(parseFloat(value) == expected_values[i]);
    }

    // Float array
    const array_str = "[1.5 14.3 44.9999 42 hello]";
    const array = try parseArrayFloat(allocator, array_str);
    defer allocator.free(array);
    const expected_array: [5]f64 = .{ 1.5, 14.3, 44.9999, 42, 0 };
    try std.testing.expect(std.mem.eql(f64, array, &expected_array));
}

test "Value parsing: String" {
    // Note that I dont parse string because I dont need to, a string is a string

    const allocator = std.testing.allocator;

    // string array
    const array_str = "['Hello' 'How are you doing ?' '']";
    const array = try parseArrayStr(allocator, array_str);
    defer allocator.free(array);
    const expected_array: [3][]const u8 = .{ "Hello", "How are you doing ?", "" };
    for (array, expected_array) |parsed, expected| {
        std.debug.print("{s} : {s}\n", .{ parsed, expected });
        try std.testing.expect(std.mem.eql(u8, parsed, expected));
    }
}

test "Value parsing: Bool array" {
    const allocator = std.testing.allocator;

    const values: [3][]const u8 = .{ "1", "Hello", "0" };
    const expected_values: [3]bool = .{ true, true, false };
    for (values, 0..) |value, i| {
        try std.testing.expect(parseBool(value) == expected_values[i]);
    }

    // Bool array
    const array_str = "[1 0 0 1 1]";
    const array = try parseArrayBool(allocator, array_str);
    defer allocator.free(array);
    const expected_array: [5]bool = .{ true, false, false, true, true };
    try std.testing.expect(std.mem.eql(bool, array, &expected_array));
}

test "Value parsing: Date" {
    const allocator = std.testing.allocator;
    // Date
    const values: [3][]const u8 = .{ "1920/01/01", "1998/01/21", "2024/12/31" };
    const expected_values: [3]DateTime = .{
        DateTime.init(1920, 1, 1, 0, 0, 0, 0),
        DateTime.init(1998, 1, 21, 0, 0, 0, 0),
        DateTime.init(2024, 12, 31, 0, 0, 0, 0),
    };
    for (values, 0..) |value, i| {
        try std.testing.expect(expected_values[i].compareDate(parseDate(value)));
    }

    // Date array
    const array_str = "[1920/01/01 1998/01/21 2024/12/31]";
    const array = try parseArrayDate(allocator, array_str);
    defer allocator.free(array);
    const expected_array: [3]DateTime = .{
        DateTime.init(1920, 1, 1, 0, 0, 0, 0),
        DateTime.init(1998, 1, 21, 0, 0, 0, 0),
        DateTime.init(2024, 12, 31, 0, 0, 0, 0),
    };
    for (array, expected_array) |parsed, expected| {
        try std.testing.expect(expected.compareDate(parsed));
    }
}

test "Value parsing: Time" {
    const allocator = std.testing.allocator;

    const values: [4][]const u8 = .{ "12:45:00.0000", "18:12:53.7491", "02:30:10", "12:30" };
    const expected_values: [4]DateTime = .{
        DateTime.init(0, 0, 0, 12, 45, 0, 0),
        DateTime.init(0, 0, 0, 18, 12, 53, 7491),
        DateTime.init(0, 0, 0, 2, 30, 10, 0),
        DateTime.init(0, 0, 0, 12, 30, 0, 0),
    };
    for (values, 0..) |value, i| {
        try std.testing.expect(expected_values[i].compareTime(parseTime(value)));
    }

    // Time array
    const array_str = "[12:45:00.0000 18:12:53.7491 02:30:10 12:30]";
    const array = try parseArrayTime(allocator, array_str);
    defer allocator.free(array);
    const expected_array: [4]DateTime = .{
        DateTime.init(0, 0, 0, 12, 45, 0, 0),
        DateTime.init(0, 0, 0, 18, 12, 53, 7491),
        DateTime.init(0, 0, 0, 2, 30, 10, 0),
        DateTime.init(0, 0, 0, 12, 30, 0, 0),
    };
    for (array, expected_array) |parsed, expected| {
        try std.testing.expect(expected.compareTime(parsed));
    }
}

test "Value parsing: Datetime" {
    const allocator = std.testing.allocator;

    const values: [4][]const u8 = .{ "1920/01/01-12:45:00.0000", "1920/01/01-18:12:53.7491", "1920/01/01-02:30:10", "1920/01/01-12:30" };
    const expected_values: [4]DateTime = .{
        DateTime.init(1920, 1, 1, 12, 45, 0, 0),
        DateTime.init(1920, 1, 1, 18, 12, 53, 7491),
        DateTime.init(1920, 1, 1, 2, 30, 10, 0),
        DateTime.init(1920, 1, 1, 12, 30, 0, 0),
    };
    for (values, 0..) |value, i| {
        try std.testing.expect(expected_values[i].compareDatetime(parseDatetime(value)));
    }

    // Time array
    const array_str = "[1920/01/01-12:45:00.0000 1920/01/01-18:12:53.7491 1920/01/01-02:30:10 1920/01/01-12:30]";
    const array = try parseArrayDatetime(allocator, array_str);
    defer allocator.free(array);
    const expected_array: [4]DateTime = .{
        DateTime.init(1920, 1, 1, 12, 45, 0, 0),
        DateTime.init(1920, 1, 1, 18, 12, 53, 7491),
        DateTime.init(1920, 1, 1, 2, 30, 10, 0),
        DateTime.init(1920, 1, 1, 12, 30, 0, 0),
    };
    for (array, expected_array) |parsed, expected| {
        try std.testing.expect(expected.compareDatetime(parsed));
    }
}
