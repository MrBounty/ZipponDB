const std = @import("std");
const UUID = @import("uuid.zig").UUID;
const DateTime = @import("date.zig").DateTime;

pub fn parseInt(value_str: []const u8) i32 {
    return std.fmt.parseInt(i32, value_str, 10) catch return 0;
}

pub fn parseFloat(value_str: []const u8) f64 {
    return std.fmt.parseFloat(f64, value_str) catch return 0;
}

pub fn parseBool(value_str: []const u8) bool {
    return (value_str[0] != '0');
}

pub fn parseDate(value_str: []const u8) DateTime {
    if (std.mem.eql(u8, value_str, "NOW")) return DateTime.now();

    const year: u16 = std.fmt.parseInt(u16, value_str[0..4], 10) catch 0;
    const month: u8 = std.fmt.parseInt(u8, value_str[5..7], 10) catch 0;
    const day: u8 = std.fmt.parseInt(u8, value_str[8..10], 10) catch 0;

    return DateTime.init(year, month - 1, day - 1, 0, 0, 0, 0);
}

pub fn parseTime(value_str: []const u8) DateTime {
    if (std.mem.eql(u8, value_str, "NOW")) return DateTime.now();

    const hours: u8 = std.fmt.parseInt(u8, value_str[0..2], 10) catch 0;
    const minutes: u8 = std.fmt.parseInt(u8, value_str[3..5], 10) catch 0;
    const seconds: u8 = if (value_str.len > 6) std.fmt.parseInt(u8, value_str[6..8], 10) catch 0 else 0;
    const milliseconds: u16 = if (value_str.len > 9) std.fmt.parseInt(u16, value_str[9..13], 10) catch 0 else 0;

    return DateTime.init(0, 0, 0, hours, minutes, seconds, milliseconds);
}

pub fn parseDatetime(value_str: []const u8) DateTime {
    if (std.mem.eql(u8, value_str, "NOW")) return DateTime.now();

    const year: u16 = std.fmt.parseInt(u16, value_str[0..4], 10) catch 0;
    const month: u8 = std.fmt.parseInt(u8, value_str[5..7], 10) catch 0;
    const day: u8 = std.fmt.parseInt(u8, value_str[8..10], 10) catch 0;
    const hours: u8 = std.fmt.parseInt(u8, value_str[11..13], 10) catch 0;
    const minutes: u8 = std.fmt.parseInt(u8, value_str[14..16], 10) catch 0;
    const seconds: u8 = if (value_str.len > 17) std.fmt.parseInt(u8, value_str[17..19], 10) catch 0 else 0;
    const milliseconds: u16 = if (value_str.len > 20) std.fmt.parseInt(u16, value_str[20..24], 10) catch 0 else 0;

    return DateTime.init(year, month - 1, day - 1, hours, minutes, seconds, milliseconds);
}

test "Value parsing: Int" {
    const values: [3][]const u8 = .{ "1", "42", "Hello" };
    const expected_values: [3]i32 = .{ 1, 42, 0 };
    for (values, 0..) |value, i| {
        try std.testing.expect(parseInt(value) == expected_values[i]);
    }
}

test "Value parsing: Float" {
    const values: [3][]const u8 = .{ "1.3", "65.991", "Hello" };
    const expected_values: [3]f64 = .{ 1.3, 65.991, 0 };
    for (values, 0..) |value, i| {
        try std.testing.expect(parseFloat(value) == expected_values[i]);
    }
}

test "Value parsing: Bool array" {
    const values: [3][]const u8 = .{ "1", "Hello", "0" };
    const expected_values: [3]bool = .{ true, true, false };
    for (values, 0..) |value, i| {
        try std.testing.expect(parseBool(value) == expected_values[i]);
    }
}

test "Value parsing: Date" {
    const values: [3][]const u8 = .{ "1920/01/01", "1998/01/21", "2024/12/31" };
    const expected_values: [3]DateTime = .{
        DateTime.init(1920, 0, 0, 0, 0, 0, 0),
        DateTime.init(1998, 0, 20, 0, 0, 0, 0),
        DateTime.init(2024, 11, 30, 0, 0, 0, 0),
    };
    for (values, 0..) |value, i| {
        try std.testing.expect(expected_values[i].compareDate(parseDate(value)));
    }
}

test "Value parsing: Time" {
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
}

test "Value parsing: Datetime" {
    const values: [4][]const u8 = .{ "1920/01/01-12:45:00.0000", "1920/01/01-18:12:53.7491", "1920/01/01-02:30:10", "1920/01/01-12:30" };
    const expected_values: [4]DateTime = .{
        DateTime.init(1920, 0, 0, 12, 45, 0, 0),
        DateTime.init(1920, 0, 0, 18, 12, 53, 7491),
        DateTime.init(1920, 0, 0, 2, 30, 10, 0),
        DateTime.init(1920, 0, 0, 12, 30, 0, 0),
    };
    for (values, 0..) |value, i| {
        try std.testing.expect(expected_values[i].compareDatetime(parseDatetime(value)));
    }
}
