// Fast allocation-free v4 UUIDs.
// Inspired by the Go implementation at github.com/skeeto/uuid

const std = @import("std");
const crypto = std.crypto;
const fmt = std.fmt;
const testing = std.testing;

pub const Error = error{InvalidUUID};

pub const UUID = struct {
    bytes: [16]u8,

    pub fn init() UUID {
        var uuid = UUID{ .bytes = undefined };

        crypto.random.bytes(&uuid.bytes);
        // Version 4
        uuid.bytes[6] = (uuid.bytes[6] & 0x0f) | 0x40;
        // Variant 1
        uuid.bytes[8] = (uuid.bytes[8] & 0x3f) | 0x80;
        return uuid;
    }

    pub fn compare(self: UUID, other: UUID) bool {
        return std.meta.eql(self.bytes, other.bytes);
    }

    fn to_string(self: UUID, slice: []u8) void {
        var string: [36]u8 = format_uuid(self);
        std.mem.copyForwards(u8, slice, &string);
    }

    pub fn format_uuid(self: UUID) [36]u8 {
        var buf: [36]u8 = undefined;
        buf[8] = '-';
        buf[13] = '-';
        buf[18] = '-';
        buf[23] = '-';
        inline for (encoded_pos, 0..) |i, j| {
            buf[i + 0] = hex[self.bytes[j] >> 4];
            buf[i + 1] = hex[self.bytes[j] & 0x0f];
        }
        return buf;
    }

    // Indices in the UUID string representation for each byte.
    const encoded_pos = [16]u8{ 0, 2, 4, 6, 9, 11, 14, 16, 19, 21, 24, 26, 28, 30, 32, 34 };

    // Hex
    const hex = "0123456789abcdef";

    // Hex to nibble mapping.
    const hex_to_nibble = [256]u8{
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x08, 0x09, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    };

    pub fn format(
        self: UUID,
        comptime layout: []const u8,
        options: fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options; // currently unused

        if (layout.len != 0 and layout[0] != 's')
            @compileError("Unsupported format specifier for UUID type: '" ++ layout ++ "'.");

        const buf = format_uuid(self);
        try fmt.format(writer, "{s}", .{buf});
    }

    pub fn parse(buf: []const u8) Error!UUID {
        var uuid = UUID{ .bytes = undefined };

        if (buf.len != 36 or buf[8] != '-' or buf[13] != '-' or buf[18] != '-' or buf[23] != '-')
            return Error.InvalidUUID;

        inline for (encoded_pos, 0..) |i, j| {
            const hi = hex_to_nibble[buf[i + 0]];
            const lo = hex_to_nibble[buf[i + 1]];
            if (hi == 0xff or lo == 0xff) {
                return Error.InvalidUUID;
            }
            uuid.bytes[j] = hi << 4 | lo;
        }

        return uuid;
    }
};

// Zero UUID
pub const zero: UUID = .{ .bytes = .{0} ** 16 };

// TODO: Optimize both
pub fn OR(arr1: *std.ArrayList(UUID), arr2: *std.ArrayList(UUID)) !void {
    for (0..arr2.items.len) |i| {
        if (!containUUID(arr1.*, arr2.items[i])) {
            try arr1.append(arr2.items[i]);
        }
    }
}

pub fn AND(arr1: *std.ArrayList(UUID), arr2: *std.ArrayList(UUID)) !void {
    var i: usize = 0;
    for (0..arr1.items.len) |_| {
        if (!containUUID(arr2.*, arr1.items[i])) {
            _ = arr1.orderedRemove(i);
        } else {
            i += 1;
        }
    }
}

test "OR & AND" {
    const allocator = std.testing.allocator;

    var right_arr = std.ArrayList(UUID).init(allocator);
    defer right_arr.deinit();
    try right_arr.append(try UUID.parse("00000000-0000-0000-0000-000000000000"));
    try right_arr.append(try UUID.parse("00000000-0000-0000-0000-000000000001"));
    try right_arr.append(try UUID.parse("00000000-0000-0000-0000-000000000005"));
    try right_arr.append(try UUID.parse("00000000-0000-0000-0000-000000000006"));
    try right_arr.append(try UUID.parse("00000000-0000-0000-0000-000000000007"));

    var left_arr1 = std.ArrayList(UUID).init(allocator);
    defer left_arr1.deinit();
    try left_arr1.append(try UUID.parse("00000000-0000-0000-0000-000000000000"));
    try left_arr1.append(try UUID.parse("00000000-0000-0000-0000-000000000001"));
    try left_arr1.append(try UUID.parse("00000000-0000-0000-0000-000000000002"));
    try left_arr1.append(try UUID.parse("00000000-0000-0000-0000-000000000003"));
    try left_arr1.append(try UUID.parse("00000000-0000-0000-0000-000000000004"));

    var expected_arr1 = std.ArrayList(UUID).init(allocator);
    defer expected_arr1.deinit();
    try expected_arr1.append(try UUID.parse("00000000-0000-0000-0000-000000000000"));
    try expected_arr1.append(try UUID.parse("00000000-0000-0000-0000-000000000001"));

    try AND(&left_arr1, &right_arr);
    try std.testing.expect(compareUUIDArray(left_arr1, expected_arr1));

    var left_arr2 = std.ArrayList(UUID).init(allocator);
    defer left_arr2.deinit();
    try left_arr2.append(try UUID.parse("00000000-0000-0000-0000-000000000000"));
    try left_arr2.append(try UUID.parse("00000000-0000-0000-0000-000000000001"));
    try left_arr2.append(try UUID.parse("00000000-0000-0000-0000-000000000002"));
    try left_arr2.append(try UUID.parse("00000000-0000-0000-0000-000000000003"));
    try left_arr2.append(try UUID.parse("00000000-0000-0000-0000-000000000004"));

    var expected_arr2 = std.ArrayList(UUID).init(allocator);
    defer expected_arr2.deinit();
    try expected_arr2.append(try UUID.parse("00000000-0000-0000-0000-000000000000"));
    try expected_arr2.append(try UUID.parse("00000000-0000-0000-0000-000000000001"));
    try expected_arr2.append(try UUID.parse("00000000-0000-0000-0000-000000000002"));
    try expected_arr2.append(try UUID.parse("00000000-0000-0000-0000-000000000003"));
    try expected_arr2.append(try UUID.parse("00000000-0000-0000-0000-000000000004"));
    try expected_arr2.append(try UUID.parse("00000000-0000-0000-0000-000000000005"));
    try expected_arr2.append(try UUID.parse("00000000-0000-0000-0000-000000000006"));
    try expected_arr2.append(try UUID.parse("00000000-0000-0000-0000-000000000007"));

    try OR(&left_arr2, &right_arr);

    try std.testing.expect(compareUUIDArray(left_arr2, expected_arr2));
}

fn containUUID(arr: std.ArrayList(UUID), value: UUID) bool {
    return for (arr.items) |elem| {
        if (value.compare(elem)) break true;
    } else false;
}

fn compareUUIDArray(arr1: std.ArrayList(UUID), arr2: std.ArrayList(UUID)) bool {
    if (arr1.items.len != arr2.items.len) {
        std.debug.print("Not same array len when comparing UUID. arr1: {d} arr2: {d}\n", .{ arr1.items.len, arr2.items.len });
        return false;
    }

    for (0..arr1.items.len) |i| {
        if (!containUUID(arr2, arr1.items[i])) return false;
    }

    return true;
}

test "parse and format" {
    const uuids = [_][]const u8{
        "d0cd8041-0504-40cb-ac8e-d05960d205ec",
        "3df6f0e4-f9b1-4e34-ad70-33206069b995",
        "f982cf56-c4ab-4229-b23c-d17377d000be",
        "6b9f53be-cf46-40e8-8627-6b60dc33def8",
        "c282ec76-ac18-4d4a-8a29-3b94f5c74813",
        "00000000-0000-0000-0000-000000000000",
    };

    for (uuids) |uuid| {
        try testing.expectFmt(uuid, "{}", .{try UUID.parse(uuid)});
    }
}

test "invalid UUID" {
    const uuids = [_][]const u8{
        "3df6f0e4-f9b1-4e34-ad70-33206069b99", // too short
        "3df6f0e4-f9b1-4e34-ad70-33206069b9912", // too long
        "3df6f0e4-f9b1-4e34-ad70_33206069b9912", // missing or invalid group separator
        "zdf6f0e4-f9b1-4e34-ad70-33206069b995", // invalid character
    };

    for (uuids) |uuid| {
        try testing.expectError(Error.InvalidUUID, UUID.parse(uuid));
    }
}

test "check to_string works" {
    const uuid1 = UUID.init();

    var string1: [36]u8 = undefined;
    var string2: [36]u8 = undefined;

    uuid1.to_string(&string1);
    uuid1.to_string(&string2);

    try testing.expectEqual(string1, string2);
}

test "compare" {
    const uuid1 = UUID.init();
    const uuid2 = UUID.init();

    try testing.expect(uuid1.compare(uuid1));
    try testing.expect(!uuid1.compare(uuid2));
}
