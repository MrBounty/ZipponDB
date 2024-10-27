const std = @import("std");
const UUID = @import("uuid.zig").UUID;
const DateTime = @import("date.zig").DateTime;

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

// TODO: Optimize all date parsing
pub fn parseDate(value_str: []const u8) DateTime {
    const year: u16 = std.fmt.parseInt(u16, value_str[0..4], 10) catch 0;
    const month: u16 = std.fmt.parseInt(u16, value_str[5..7], 10) catch 0;
    const day: u16 = std.fmt.parseInt(u16, value_str[8..10], 10) catch 0;

    return DateTime.init(year, month, day, 0, 0, 0, 0);
}

pub fn parseArrayDate(allocator: std.mem.Allocator, array_str: []const u8) std.ArrayList(DateTime) {
    var array = std.ArrayList(DateTime).init(allocator);

    var it = std.mem.splitAny(u8, array_str[1 .. array_str.len - 1], " ");
    while (it.next()) |x| {
        array.append(parseDate(x)) catch {};
    }

    return array;
}

pub fn parseTime(value_str: []const u8) DateTime {
    const hours: u16 = std.fmt.parseInt(u16, value_str[0..2], 10) catch 0;
    const minutes: u16 = std.fmt.parseInt(u16, value_str[3..5], 10) catch 0;
    const seconds: u16 = if (value_str.len > 6) std.fmt.parseInt(u16, value_str[6..8], 10) catch 0 else 0;
    const milliseconds: u16 = if (value_str.len > 9) std.fmt.parseInt(u16, value_str[9..13], 10) catch 0 else 0;

    return DateTime.init(0, 0, 0, hours, minutes, seconds, milliseconds);
}

pub fn parseArrayTime(allocator: std.mem.Allocator, array_str: []const u8) std.ArrayList(DateTime) {
    var array = std.ArrayList(DateTime).init(allocator);

    var it = std.mem.splitAny(u8, array_str[1 .. array_str.len - 1], " ");
    while (it.next()) |x| {
        array.append(parseTime(x)) catch {};
    }

    return array;
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

pub fn parseArrayDatetime(allocator: std.mem.Allocator, array_str: []const u8) std.ArrayList(DateTime) {
    var array = std.ArrayList(DateTime).init(allocator);

    var it = std.mem.splitAny(u8, array_str[1 .. array_str.len - 1], " ");
    while (it.next()) |x| {
        array.append(parseDatetime(x)) catch {};
    }

    return array;
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

// FIXME: I think it will not work if there is a ' inside the string, even \', need to fix that
pub fn parseArrayStr(allocator: std.mem.Allocator, array_str: []const u8) std.ArrayList([]const u8) {
    var array = std.ArrayList([]const u8).init(allocator);

    var it = std.mem.splitAny(u8, array_str[1 .. array_str.len - 1], "'");
    _ = it.next(); // SSkip first token that is empty
    while (it.next()) |x| {
        if (std.mem.eql(u8, " ", x)) continue;
        const x_copy = std.fmt.allocPrint(allocator, "'{s}'", .{x}) catch @panic("=(");
        array.append(x_copy) catch {};
    }

    allocator.free(array.pop()); // Remove the last because empty like the first one

    return array;
}

test "Value parsing: Int" {
    const allocator = std.testing.allocator;

    // Int
    const values: [3][]const u8 = .{ "1", "42", "Hello" };
    const expected_values: [3]i64 = .{ 1, 42, 0 };
    for (values, 0..) |value, i| {
        try std.testing.expect(parseInt(value) == expected_values[i]);
    }

    // Int array
    const array_str = "[1 14 44 42 hello]";
    const array = parseArrayInt(allocator, array_str);
    defer array.deinit();
    const expected_array: [5]i64 = .{ 1, 14, 44, 42, 0 };
    try std.testing.expect(std.mem.eql(i64, array.items, &expected_array));
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
    const array = parseArrayFloat(allocator, array_str);
    defer array.deinit();
    const expected_array: [5]f64 = .{ 1.5, 14.3, 44.9999, 42, 0 };
    try std.testing.expect(std.mem.eql(f64, array.items, &expected_array));
}

test "Value parsing: String" {
    // Note that I dont parse string because I dont need to, a string is a string

    const allocator = std.testing.allocator;

    // string array
    const array_str = "['Hello' 'How are you doing ?' '']";
    const array = parseArrayStr(allocator, array_str);
    defer {
        for (array.items) |parsed| {
            allocator.free(parsed);
        }
        array.deinit();
    }
    const expected_array: [3][]const u8 = .{ "'Hello'", "'How are you doing ?'", "''" };
    for (array.items, expected_array) |parsed, expected| {
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
    const array = parseArrayBool(allocator, array_str);
    defer array.deinit();
    const expected_array: [5]bool = .{ true, false, false, true, true };
    try std.testing.expect(std.mem.eql(bool, array.items, &expected_array));
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
    const array = parseArrayDate(allocator, array_str);
    defer array.deinit();
    const expected_array: [3]DateTime = .{
        DateTime.init(1920, 1, 1, 0, 0, 0, 0),
        DateTime.init(1998, 1, 21, 0, 0, 0, 0),
        DateTime.init(2024, 12, 31, 0, 0, 0, 0),
    };
    for (array.items, expected_array) |parsed, expected| {
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
    const array = parseArrayTime(allocator, array_str);
    defer array.deinit();
    const expected_array: [4]DateTime = .{
        DateTime.init(0, 0, 0, 12, 45, 0, 0),
        DateTime.init(0, 0, 0, 18, 12, 53, 7491),
        DateTime.init(0, 0, 0, 2, 30, 10, 0),
        DateTime.init(0, 0, 0, 12, 30, 0, 0),
    };
    for (array.items, expected_array) |parsed, expected| {
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
    const array = parseArrayDatetime(allocator, array_str);
    defer array.deinit();
    const expected_array: [4]DateTime = .{
        DateTime.init(1920, 1, 1, 12, 45, 0, 0),
        DateTime.init(1920, 1, 1, 18, 12, 53, 7491),
        DateTime.init(1920, 1, 1, 2, 30, 10, 0),
        DateTime.init(1920, 1, 1, 12, 30, 0, 0),
    };
    for (array.items, expected_array) |parsed, expected| {
        try std.testing.expect(expected.compareDatetime(parsed));
    }
}
