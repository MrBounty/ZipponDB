const std = @import("std");
const UUID = @import("dtype").UUID;
const ArenaAllocator = std.heap.ArenaAllocator;

// Maube use that later, the point is that it take only 16 comparison per UUID and save a lot of memory
// But now that I think about it, 16 comparison vs 1, you get me
pub const UUIDTree = struct {
    arena: *ArenaAllocator,
    root_node: Node,
    len: usize,

    pub fn init(allocator: std.mem.Allocator) UUIDTree {
        var arena = ArenaAllocator.init(allocator);
        return UUIDTree{ .arena = &arena, .root_node = Node.init(&arena, 0), .len = 0 };
    }

    pub fn deinit(self: *UUIDTree) void {
        self.arena.deinit();
    }

    pub fn add(self: *UUIDTree, uuid: UUID) void {
        if (self.root_node.add(uuid, self.arena)) self.len += 1;
    }

    pub fn isIn(self: UUIDTree, uuid: UUID) bool {
        return self.root_node.evaluate(uuid);
    }
};

const Node = struct {
    depth: u4, // Because a UUID is 16 len and u4 have 16 different value
    map: std.AutoHashMap(u8, ?Node),

    fn init(arena: *ArenaAllocator, depth: u4) Node {
        const allocator = arena.*.allocator();
        return Node{
            .depth = depth,
            .map = std.AutoHashMap(u8, ?Node).init(allocator),
        };
    }
    fn evaluate(self: Node, _: UUID) bool {
        return switch (self.depth) {
            15 => true,
            else => false,
        };
    }

    fn add(self: *Node, uuid: UUID, arena: *ArenaAllocator) bool {
        switch (self.depth) {
            15 => {
                const c = uuid.bytes[self.depth];
                std.debug.print("{b}\n", .{c});

                if (self.map.get(c)) |_| {
                    std.debug.print("UUID already in map\n", .{});
                    return false;
                } else {
                    self.map.put(c, null) catch return false;
                    return true;
                }
            },
            else => {
                const c = uuid.bytes[self.depth];
                std.debug.print("{b}\n", .{c});

                // Could use getOrPut for perf I think
                if (self.map.getPtr(c)) |next_node| {
                    return next_node.*.?.add(uuid, arena);
                } else {
                    var new_node = Node.init(arena, self.depth + 1);
                    self.map.put(c, new_node) catch return false;
                    return new_node.add(uuid, arena);
                }
            },
        }
    }
};
