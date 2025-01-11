const std = @import("std");
const UUID = @import("dtype").UUID;
const ArenaAllocator = std.heap.ArenaAllocator;

pub const UUIDIndexMap = @This();

arena: *ArenaAllocator,
map: *std.AutoHashMap(UUID, usize),

pub fn init(allocator: std.mem.Allocator) !UUIDIndexMap {
    const arena = try allocator.create(ArenaAllocator);
    errdefer allocator.destroy(arena);
    arena.* = ArenaAllocator.init(allocator);

    const map = try arena.allocator().create(std.AutoHashMap(UUID, usize));
    map.* = std.AutoHashMap(UUID, usize).init(arena.allocator());

    return UUIDIndexMap{
        .map = map,
        .arena = arena,
    };
}

pub fn deinit(self: *UUIDIndexMap) void {
    const allocator = self.arena.child_allocator;
    self.arena.deinit();
    allocator.destroy(self.arena);
}

pub fn put(self: *UUIDIndexMap, uuid: UUID, file_index: usize) !void {
    try self.map.*.put(uuid, file_index);
}

pub fn contains(self: UUIDIndexMap, uuid: UUID) bool {
    return self.map.contains(uuid);
}

pub fn get(self: UUIDIndexMap, uuid: UUID) ?usize {
    return self.map.get(uuid);
}

test "Create empty UUIDIndexMap" {
    const allocator = std.testing.allocator;

    var imap = try UUIDIndexMap.init(allocator);
    defer imap.deinit();
}

test "Get UUID in UUIDIndexMap" {
    const allocator = std.testing.allocator;

    var imap = try UUIDIndexMap.init(allocator);
    defer imap.deinit();

    const uuid = try UUID.parse("00000000-0000-0000-0000-000000000000");

    try imap.put(uuid, 0);
    const expected: usize = 0;
    try std.testing.expectEqual(imap.get(uuid), expected);
}

test "Update UUID in UUIDIndexMap" {
    const allocator = std.testing.allocator;

    var imap = try UUIDIndexMap.init(allocator);
    defer imap.deinit();

    const uuid = try UUID.parse("00000000-0000-0000-0000-000000000000");

    for (0..1000) |i| {
        try imap.put(uuid, i);
        try std.testing.expectEqual(imap.get(uuid), i);
    }
}

test "UUIDIndexMap multiple keys" {
    const allocator = std.testing.allocator;

    var imap = try UUIDIndexMap.init(allocator);
    defer imap.deinit();

    const uuid0 = try UUID.parse("00000000-0000-0000-0000-000000000000");
    const uuid1 = try UUID.parse("00000000-0000-0000-0000-000000000001");
    const uuid2 = try UUID.parse("00000000-0000-0000-0000-000000000002");
    try imap.put(uuid0, 0);
    try imap.put(uuid1, 1);
    try imap.put(uuid2, 2);

    try std.testing.expect(imap.contains(uuid0));
    try std.testing.expect(imap.contains(uuid1));
    try std.testing.expect(imap.contains(uuid2));

    const expected_values = [_]usize{ 0, 1, 2 };
    try std.testing.expectEqual(imap.get(uuid0), expected_values[0]);
    try std.testing.expectEqual(imap.get(uuid1), expected_values[1]);
    try std.testing.expectEqual(imap.get(uuid2), expected_values[2]);
}

test "Multiple Node UUIDIndexMap with Deep Subdivisions" {
    const allocator = std.testing.allocator;

    var imap = try UUIDIndexMap.init(allocator);
    defer imap.deinit();

    const uuids = [_][]const u8{
        "00000000-0000-0000-0000-000000000000",
        "00000000-0000-0000-0000-000000000001",
        "00000000-0000-0000-0000-000000000002",
        "10000000-0000-0000-0000-000000000000",
        "11000000-0000-0000-0000-000000000000",
        "11100000-0000-0000-0000-000000000000",
        "11110000-0000-0000-0000-000000000000",
        "11111000-0000-0000-0000-000000000000",
        "11111100-0000-0000-0000-000000000000",
        "11111110-0000-0000-0000-000000000000",
        "11111111-0000-0000-0000-000000000000",
    };

    // Insert UUIDs
    for (uuids, 0..) |uuid_str, i| {
        const uuid = try UUID.parse(uuid_str);
        try imap.put(uuid, i);
    }

    // Test contains and get
    for (uuids, 0..) |uuid_str, i| {
        const uuid = try UUID.parse(uuid_str);
        try std.testing.expect(imap.contains(uuid));
        try std.testing.expectEqual(imap.get(uuid).?, i);
    }

    // Test non-existent UUIDs
    const non_existent_uuids = [_][]const u8{
        "ffffffff-ffff-ffff-ffff-ffffffffffff",
        "22222222-2222-2222-2222-222222222222",
        "11111111-1111-1111-1111-111111111111",
    };

    for (non_existent_uuids) |uuid_str| {
        const uuid = try UUID.parse(uuid_str);
        try std.testing.expect(!imap.contains(uuid));
        try std.testing.expectEqual(imap.get(uuid), null);
    }

    // Test partial matches
    const partial_matches = [_]struct { uuid: []const u8, expected_value: ?usize }{
        .{ .uuid = "00000000-0000-0000-0000-000000000003", .expected_value = null },
        .{ .uuid = "10000000-0000-0000-0000-000000000001", .expected_value = null },
        .{ .uuid = "11100000-0000-0000-0000-000000000001", .expected_value = null },
        .{ .uuid = "11111111-1000-0000-0000-000000000000", .expected_value = null },
    };

    for (partial_matches) |pm| {
        const uuid = try UUID.parse(pm.uuid);
        try std.testing.expectEqual(pm.expected_value, imap.get(uuid));
    }
}

test "UUIDIndexMap benchmark" {
    const allocator = std.testing.allocator;

    var imap = try UUIDIndexMap.init(allocator);
    defer imap.deinit();

    for (0..1_000_000) |_| {
        const uuid = UUID.init();
        try imap.put(uuid, 0);
        _ = imap.contains(uuid);
    }

    const mb: f64 = @as(f64, @floatFromInt(imap.arena.queryCapacity())) / 1024.0 / 1024.0;
    std.debug.print("Memory use for 1 000 000: {d}MB\n", .{mb});
}
