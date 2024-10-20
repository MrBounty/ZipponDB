pub const Node = struct {
    prev: ?*Node = null,
    next: ?*Node = null,
    query: []const u8,
};
