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
const ZipponError = @import("errors.zig").ZipponError;
const DataType = @import("dtype").DataType;

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

pub const Condition = struct {
    value: []const u8 = undefined,
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

    fn freeNode(self: *Filter, node: *FilterNode) void {
        switch (node.*) {
            .logical => |logical| {
                self.freeNode(logical.left);
                self.freeNode(logical.right);
                self.allocator.destroy(logical.left);
                self.allocator.destroy(logical.right);
            },
            .condition => {},
            .empty => {},
        }
    }

    // TODO: Use []Data and make it work
    pub fn evaluate(self: *const Filter, row: anytype) bool {
        return self.evaluateNode(&self.root, row);
    }

    fn evaluateNode(self: *const Filter, node: *const FilterNode, row: anytype) bool {
        return switch (node.*) {
            .condition => |cond| self.evaluateCondition(cond, row),
            .logical => |log| switch (log.operator) {
                .AND => self.evaluateNode(log.left, row) and self.evaluateNode(log.right, row),
                .OR => self.evaluateNode(log.left, row) or self.evaluateNode(log.right, row),
            },
        };
    }

    fn evaluateCondition(condition: Condition, row: anytype) bool {
        const field_value = @field(row, condition.member_name);
        return switch (condition.operation) {
            .equal => std.mem.eql(u8, field_value, condition.value),
            .different => !std.mem.eql(u8, field_value, condition.value),
            .superior => field_value > condition.value,
            .superior_or_equal => field_value >= condition.value,
            .inferior => field_value < condition.value,
            .inferior_or_equal => field_value <= condition.value,
            .in => @panic("Not implemented"), // Implement this based on your needs
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
            .condition => |condition| std.debug.print("{d} {s} {s} |{any}|", .{
                condition.data_index,
                condition.operation.str(),
                condition.value,
                condition.data_type,
            }),
            .empty => std.debug.print("Empty", .{}),
        }
    }
};
