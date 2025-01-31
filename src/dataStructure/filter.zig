// Should do a tree like that:
//            AND
//         /      \
//        OR      OR
//       / \      / \
//    name name age age
//    ='A' ='B' >80 <20
//
// For {(name = 'Adrien' OR name = 'Bob') AND (age > 80 OR age < 20)}

const std = @import("std");
const s2t = @import("dtype").s2t;
const ZipponError = @import("error").ZipponError;
const DataType = @import("dtype").DataType;
const DateTime = @import("dtype").DateTime;
const UUID = @import("dtype").UUID;
const Data = @import("ZipponData").Data;

const log = std.log.scoped(.filter);

pub const ComparisonOperator = enum {
    equal,
    different,
    superior,
    superior_or_equal,
    inferior,
    inferior_or_equal,
    in,
    not_in,

    pub fn str(self: ComparisonOperator) []const u8 {
        return switch (self) {
            .equal => "=",
            .different => "!=",
            .superior => ">",
            .superior_or_equal => ">=",
            .inferior => "<",
            .inferior_or_equal => "<=",
            .in => "IN",
            .not_in => "!IN",
        };
    }
};

const LogicalOperator = enum {
    AND,
    OR,

    pub fn str(self: LogicalOperator) []const u8 {
        return switch (self) {
            .AND => "AND",
            .OR => "OR",
        };
    }
};

pub const ConditionValue = union(enum) {
    int: i32,
    float: f64,
    str: []const u8,
    bool_: bool,
    self: UUID,
    unix: u64,
    int_array: []const i32,
    str_array: []const []const u8,
    float_array: []const f64,
    bool_array: []const bool,
    unix_array: []const u64,
    link: *const std.AutoHashMap(UUID, void),
    link_array: *const std.AutoHashMap(UUID, void),

    pub fn init(dtype: DataType, value: []const u8) ConditionValue {
        return switch (dtype) {
            .int => ConditionValue.initInt(value),
            .float => ConditionValue.initFloat(value),
            .bool => ConditionValue.initBool(value),
            .date => ConditionValue.initDate(value),
            .time => ConditionValue.initTime(value),
            .datetime => ConditionValue.initDateTime(value),
            .str => ConditionValue.initStr(value[1 .. value.len - 1]),
        };
    }

    pub fn initInt(value: []const u8) ConditionValue {
        return ConditionValue{ .int = s2t.parseInt(value) };
    }

    pub fn initFloat(value: []const u8) ConditionValue {
        return ConditionValue{ .float = s2t.parseFloat(value) };
    }

    pub fn initStr(value: []const u8) ConditionValue {
        return ConditionValue{ .str = value };
    }

    pub fn initSelf(value: UUID) ConditionValue {
        return ConditionValue{ .self = value };
    }

    pub fn initBool(value: []const u8) ConditionValue {
        return ConditionValue{ .bool_ = s2t.parseBool(value) };
    }

    pub fn initDate(value: []const u8) ConditionValue {
        return ConditionValue{ .unix = s2t.parseDate(value).toUnix() };
    }

    pub fn initTime(value: []const u8) ConditionValue {
        return ConditionValue{ .unix = s2t.parseTime(value).toUnix() };
    }

    pub fn initDateTime(value: []const u8) ConditionValue {
        return ConditionValue{ .unix = s2t.parseDatetime(value).toUnix() };
    }

    // Array
    pub fn initArrayInt(value: []const i32) ZipponError!ConditionValue {
        return ConditionValue{ .int_array = value };
    }

    pub fn initArrayFloat(value: []const f64) ZipponError!ConditionValue {
        return ConditionValue{ .float_array = value };
    }

    pub fn initArrayStr(value: []const []const u8) ZipponError!ConditionValue {
        return ConditionValue{ .str_array = value };
    }

    pub fn initArrayBool(value: []const bool) ZipponError!ConditionValue {
        return ConditionValue{ .bool_array = value };
    }

    pub fn initArrayUnix(value: []const u64) ZipponError!ConditionValue {
        return ConditionValue{ .unix_array = value };
    }

    pub fn initLink(value: *const std.AutoHashMap(UUID, void)) ConditionValue {
        return ConditionValue{ .link = value };
    }

    pub fn initArrayLink(value: *const std.AutoHashMap(UUID, void)) ConditionValue {
        return ConditionValue{ .link_array = value };
    }
};

pub const Condition = struct {
    value: ConditionValue = undefined,
    operation: ComparisonOperator = undefined,
    data_type: DataType = undefined,
    data_index: usize = undefined, // Index in the file
};

const FilterNode = union(enum) {
    condition: Condition,
    logical: struct {
        operator: LogicalOperator,
        left: *FilterNode,
        right: *FilterNode,
    },
    empty: bool,
};

pub const Filter = struct {
    allocator: std.mem.Allocator,
    root: *FilterNode,

    pub fn init(allocator: std.mem.Allocator) ZipponError!Filter {
        const node = allocator.create(FilterNode) catch return ZipponError.MemoryError;
        node.* = FilterNode{ .empty = true };
        return .{ .allocator = allocator, .root = node };
    }

    pub fn deinit(self: *Filter) void {
        switch (self.root.*) {
            .logical => self.freeNode(self.root),
            else => {},
        }
        self.allocator.destroy(self.root);
    }

    fn freeNode(self: *Filter, node: *FilterNode) void {
        switch (node.*) {
            .logical => |logical| {
                self.freeNode(logical.left);
                self.freeNode(logical.right);
                self.allocator.destroy(logical.left);
                self.allocator.destroy(logical.right);
            },
            else => {},
        }
    }

    pub fn addCondition(self: *Filter, condition: Condition) ZipponError!void {
        const node = self.allocator.create(FilterNode) catch return ZipponError.MemoryError;
        node.* = FilterNode{ .condition = condition };
        switch (self.root.*) {
            .empty => {
                self.allocator.destroy(self.root);
                self.root = node;
            },
            .logical => {
                var current = self.root;
                var founded = false;
                while (!founded) switch (current.logical.right.*) {
                    .empty => founded = true,
                    .logical => {
                        current = current.logical.right;
                        founded = false;
                    },
                    .condition => unreachable,
                };
                self.allocator.destroy(current.logical.right);
                current.logical.right = node;
            },
            .condition => unreachable,
        }
    }

    pub fn addLogicalOperator(self: *Filter, operator: LogicalOperator) ZipponError!void {
        const empty_node = self.allocator.create(FilterNode) catch return ZipponError.MemoryError;
        empty_node.* = FilterNode{ .empty = true };

        const node = self.allocator.create(FilterNode) catch return ZipponError.MemoryError;
        node.* = FilterNode{ .logical = .{ .operator = operator, .left = self.root, .right = empty_node } };
        self.root = node;
    }

    pub fn addSubFilter(self: *Filter, sub_filter: *Filter) void {
        switch (self.root.*) {
            .empty => {
                self.allocator.destroy(self.root);
                self.root = sub_filter.root;
            },
            .logical => {
                var current = self.root;
                var founded = false;
                while (!founded) switch (current.logical.right.*) {
                    .empty => founded = true,
                    .logical => {
                        current = current.logical.right;
                        founded = false;
                    },
                    .condition => unreachable,
                };
                self.allocator.destroy(current.logical.right);
                current.logical.right = sub_filter.root;
            },
            .condition => unreachable,
        }
    }

    pub fn evaluate(self: Filter, row: []Data) bool {
        return self.evaluateNode(self.root, row);
    }

    fn evaluateNode(self: Filter, node: *FilterNode, row: []Data) bool {
        return switch (node.*) {
            .condition => |cond| Filter.evaluateCondition(cond, row[cond.data_index]),
            .logical => |logical| switch (logical.operator) {
                .AND => self.evaluateNode(logical.left, row) and self.evaluateNode(logical.right, row),
                .OR => self.evaluateNode(logical.left, row) or self.evaluateNode(logical.right, row),
            },
            .empty => true,
        };
    }

    fn evaluateCondition(condition: Condition, row_value: Data) bool {
        return switch (condition.operation) {
            .equal => switch (condition.data_type) {
                .int => row_value.Int == condition.value.int,
                .float => row_value.Float == condition.value.float,
                .str => std.mem.eql(u8, row_value.Str, condition.value.str),
                .bool => row_value.Bool == condition.value.bool_,
                .date, .time, .datetime => row_value.Unix == condition.value.unix,
                else => unreachable,
            },

            .different => switch (condition.data_type) {
                .int => row_value.Int != condition.value.int,
                .float => row_value.Float != condition.value.float,
                .str => !std.mem.eql(u8, row_value.Str, condition.value.str),
                .bool => row_value.Bool != condition.value.bool_,
                .date, .time, .datetime => row_value.Unix != condition.value.unix,
                else => unreachable,
            },

            .superior_or_equal => switch (condition.data_type) {
                .int => row_value.Int >= condition.value.int,
                .float => row_value.Float >= condition.value.float,
                .date, .time, .datetime => row_value.Unix >= condition.value.unix,
                else => unreachable,
            },

            .superior => switch (condition.data_type) {
                .int => row_value.Int > condition.value.int,
                .float => row_value.Float > condition.value.float,
                .date, .time, .datetime => row_value.Unix > condition.value.unix,
                else => unreachable,
            },

            .inferior_or_equal => switch (condition.data_type) {
                .int => row_value.Int <= condition.value.int,
                .float => row_value.Float <= condition.value.float,
                .date, .time, .datetime => row_value.Unix <= condition.value.unix,
                else => unreachable,
            },

            .inferior => switch (condition.data_type) {
                .int => row_value.Int < condition.value.int,
                .float => row_value.Float < condition.value.float,
                .date, .time, .datetime => row_value.Unix < condition.value.unix,
                else => unreachable,
            },

            // TODO: Also be able to it for array to array. Like names in ['something']
            // And it is true if at least one value are shared between array.
            .in => switch (condition.data_type) {
                .link => condition.value.link.contains(UUID{ .bytes = row_value.UUID }),
                .int => in(i32, row_value.Int, condition.value.int_array),
                .float => in(f64, row_value.Float, condition.value.float_array),
                .str => inStr(row_value.Str, condition.value.str_array),
                .bool => in(bool, row_value.Bool, condition.value.bool_array),
                .date => in(u64, row_value.Unix, condition.value.unix_array),
                .time => in(u64, row_value.Unix, condition.value.unix_array),
                .datetime => in(u64, row_value.Unix, condition.value.unix_array),
                else => unreachable,
            },

            .not_in => switch (condition.data_type) {
                .link => !condition.value.link.contains(UUID{ .bytes = row_value.UUID }),
                .int => !in(i32, row_value.Int, condition.value.int_array),
                .float => !in(f64, row_value.Float, condition.value.float_array),
                .str => !inStr(row_value.Str, condition.value.str_array),
                .bool => !in(bool, row_value.Bool, condition.value.bool_array),
                .date => !in(u64, row_value.Unix, condition.value.unix_array),
                .time => !in(u64, row_value.Unix, condition.value.unix_array),
                .datetime => !in(u64, row_value.Unix, condition.value.unix_array),
                else => unreachable,
            },
        };
    }

    pub fn debugPrint(self: Filter) void {
        self.printNode(self.root.*);
        std.debug.print("\n", .{});
    }

    fn printNode(self: Filter, node: FilterNode) void {
        switch (node) {
            .logical => |logical| {
                std.debug.print(" ( ", .{});
                self.printNode(logical.left.*);
                std.debug.print(" {s} ", .{logical.operator.str()});
                self.printNode(logical.right.*);
                std.debug.print(" ) ", .{});
            },
            .condition => |condition| std.debug.print("{d} {s} {any} |{any}|", .{
                condition.data_index,
                condition.operation.str(),
                condition.value,
                condition.data_type,
            }),
            .empty => std.debug.print("Empty", .{}),
        }
    }

    fn in(comptime T: type, value: T, array: []const T) bool {
        for (array) |v| if (v == value) return true;
        return false;
    }

    fn inStr(value: []const u8, array: []const []const u8) bool {
        for (array) |v| if (std.mem.eql(u8, v, value)) return true;
        return false;
    }
};

test "Evaluate" {
    const allocator = std.testing.allocator;

    var data = [_]Data{
        Data.initInt(1),
        Data.initFloat(3.14159),
        Data.initInt(-5),
        Data.initStr("Hello world"),
        Data.initBool(true),
    };

    var filter = try Filter.init(allocator);
    defer filter.deinit();

    try filter.addCondition(Condition{ .value = ConditionValue.initInt("1"), .data_index = 0, .operation = .equal, .data_type = .int });

    filter.debugPrint();

    _ = filter.evaluate(&data);
}

test "ConditionValue: link" {
    const allocator = std.testing.allocator;

    // Create a hash map for storing UUIDs
    var hash_map = std.AutoHashMap(UUID, void).init(allocator);
    defer hash_map.deinit();

    // Create a UUID to add to the hash map
    const uuid1 = try UUID.parse("123e4567-e89b-12d3-a456-426614174000");
    const uuid2 = try UUID.parse("223e4567-e89b-12d3-a456-426614174000");

    // Add UUIDs to the hash map
    try hash_map.put(uuid1, {});
    try hash_map.put(uuid2, {});

    // Create a ConditionValue with the link
    var value = ConditionValue.initLink(&hash_map);

    // Check that the hash map contains the correct number of UUIDs
    try std.testing.expectEqual(@as(usize, 2), value.link.count());

    // Check that specific UUIDs are in the hash map
    try std.testing.expect(value.link.contains(uuid1));
    try std.testing.expect(value.link.contains(uuid2));
}
