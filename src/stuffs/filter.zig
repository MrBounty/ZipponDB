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
const ZipponError = @import("errors.zig").ZipponError;
const DataType = @import("dtype").DataType;
const DateTime = @import("dtype").DateTime;
const UUID = @import("dtype").UUID;
const Data = @import("ZipponData").Data;

const ComparisonOperator = enum {
    equal,
    different,
    superior,
    superior_or_equal,
    inferior,
    inferior_or_equal,
    in,

    pub fn str(self: ComparisonOperator) []const u8 {
        return switch (self) {
            .equal => "=",
            .different => "!=",
            .superior => ">",
            .superior_or_equal => ">=",
            .inferior => "<",
            .inferior_or_equal => "<=",
            .in => "IN",
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
    link: UUID,
    unix: u64,
    int_array: std.ArrayList(i32),
    str_array: std.ArrayList([]const u8),
    float_array: std.ArrayList(f64),
    bool_array: std.ArrayList(bool),
    link_array: std.ArrayList(UUID),
    unix_array: std.ArrayList(u64),

    pub fn deinit(self: ConditionValue) void {
        switch (self) {
            .int_array => self.int_array.deinit(),
            .str_array => self.str_array.deinit(),
            .float_array => self.float_array.deinit(),
            .bool_array => self.bool_array.deinit(),
            .link_array => self.link_array.deinit(),
            .unix_array => self.unix_array.deinit(),
            else => {},
        }
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
    pub fn initArrayInt(allocator: std.mem.Allocator, value: []const u8) ConditionValue {
        return ConditionValue{ .int_array = s2t.parseArrayInt(allocator, value) };
    }

    pub fn initArrayFloat(allocator: std.mem.Allocator, value: []const u8) ConditionValue {
        return ConditionValue{ .float_array = s2t.parseArrayFloat(allocator, value) };
    }

    pub fn initArrayStr(allocator: std.mem.Allocator, value: []const u8) ConditionValue {
        return ConditionValue{ .str_array = s2t.parseArrayStr(allocator, value) };
    }

    pub fn initArrayBool(allocator: std.mem.Allocator, value: []const u8) ConditionValue {
        return ConditionValue{ .bool_array = s2t.parseArrayBool(allocator, value) };
    }

    pub fn initArrayDate(allocator: std.mem.Allocator, value: []const u8) ConditionValue {
        return ConditionValue{ .unix_array = s2t.parseArrayDateUnix(allocator, value) };
    }

    pub fn initArrayTime(allocator: std.mem.Allocator, value: []const u8) ConditionValue {
        return ConditionValue{ .unix_array = s2t.parseArrayTimeUnix(allocator, value) };
    }

    pub fn initArrayDateTime(allocator: std.mem.Allocator, value: []const u8) ConditionValue {
        return ConditionValue{ .unix_array = s2t.parseArrayDatetimeUnix(allocator, value) };
    }
};

pub const Condition = struct {
    value: ConditionValue = undefined,
    operation: ComparisonOperator = undefined,
    data_type: DataType = undefined,
    data_index: usize = undefined, // Index in the file

    pub fn deinit(self: Condition) void {
        self.value.deinit();
    }
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
            .condition => |condition| condition.deinit(),
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
            .condition => |condition| condition.deinit(),
            .empty => {},
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

    // TODO: Use []Data and make it work
    pub fn evaluate(self: Filter, row: []Data) bool {
        return self.evaluateNode(self.root, row);
    }

    fn evaluateNode(self: Filter, node: *FilterNode, row: []Data) bool {
        return switch (node.*) {
            .condition => |cond| Filter.evaluateCondition(cond, row),
            .logical => |log| switch (log.operator) {
                .AND => self.evaluateNode(log.left, row) and self.evaluateNode(log.right, row),
                .OR => self.evaluateNode(log.left, row) or self.evaluateNode(log.right, row),
            },
            .empty => true,
        };
    }

    fn evaluateCondition(condition: Condition, row: []Data) bool {
        const row_value: Data = row[condition.data_index];
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

            else => false,
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
