const std = @import("std");
const zid = @import("ZipponData");
const dtype = @import("dtype");
const ConditionValue = @import("../dataStructure/filter.zig").ConditionValue;
const ArrayCondition = @import("../ziql/parts//newData.zig").ArrayCondition;

// This shouldn't be here, to move somewhere, idk yet

/// Update an array based on keyword like append or remove
pub fn updateData(allocator: std.mem.Allocator, condition: ArrayCondition, input: *zid.Data, data: ?ConditionValue) !void {
    try switch (condition) {
        .append => append(allocator, input, data.?),
        .pop => pop(allocator, input),
        .clear => clear(allocator, input),
        .remove => remove(allocator, input, data.?),
        .removeat => removeat(allocator, input, data.?),
    };
}

// This does not work, I think because I cant access the value at the pointer and so not update it.
// Maybe if I return instead ?
fn popInline(input: *zid.Data) void {
    inline for (comptime std.meta.fields(zid.Data)) |field| {
        if (comptime std.mem.endsWith(u8, field.name, "Array")) {
            if (@field(input, field.name).len > 8) { // If array is not empty, only 8 bytes mean that there is just the size of the array that's encode, meaning a u64 of 8 bytes
                @field(input.*, field.name) = @field(input, field.name)[0 .. @field(input, field.name).len - input.size()];
            }
        }
    }
}

fn pop(allocator: std.mem.Allocator, input: *zid.Data) !void {
    var updated_array = std.ArrayList(u8).init(allocator);
    errdefer updated_array.deinit();

    var new_len: ?u64 = null;
    if (input.size() > 8) switch (input.*) {
        .IntArray => |v| try updated_array.appendSlice(v[0 .. v.len - @sizeOf(i32)]),
        .FloatArray => |v| try updated_array.appendSlice(v[0 .. v.len - @sizeOf(f64)]),
        .UnixArray => |v| try updated_array.appendSlice(v[0 .. v.len - @sizeOf(u64)]),
        .UUIDArray => |v| try updated_array.appendSlice(v[0 .. v.len - @sizeOf([16]u8)]),
        .BoolArray => |v| try updated_array.appendSlice(v[0 .. v.len - @sizeOf(bool)]),
        .StrArray => |v| {
            var iter = try zid.ArrayIterator.init(input.*);
            var last_str: []const u8 = undefined;
            while (iter.next()) |item| last_str = item.Str;
            try updated_array.appendSlice(v[0 .. v.len - last_str.len - 8]);
            new_len = input.size() - 16 - last_str.len;
        },
        else => unreachable,
    } else {
        try updated_array.appendNTimes(' ', 8);
        new_len = 0;
    }

    new_len = new_len orelse updated_array.items.len - 8;

    @memcpy(updated_array.items[0..@sizeOf(u64)], std.mem.asBytes(&new_len.?));

    switch (input.*) {
        .IntArray => input.*.IntArray = try updated_array.toOwnedSlice(),
        .FloatArray => input.*.FloatArray = try updated_array.toOwnedSlice(),
        .UnixArray => input.*.UnixArray = try updated_array.toOwnedSlice(),
        .UUIDArray => input.*.UUIDArray = try updated_array.toOwnedSlice(),
        .BoolArray => input.*.BoolArray = try updated_array.toOwnedSlice(),
        .StrArray => input.*.StrArray = try updated_array.toOwnedSlice(),
        else => unreachable,
    }
}

fn clear(allocator: std.mem.Allocator, input: *zid.Data) !void {
    var updated_array = std.ArrayList(u8).init(allocator);
    errdefer updated_array.deinit();

    const new_len: u64 = 0;
    try updated_array.appendSlice(std.mem.asBytes(&new_len));

    switch (input.*) {
        .IntArray => input.*.IntArray = try updated_array.toOwnedSlice(),
        .FloatArray => input.*.FloatArray = try updated_array.toOwnedSlice(),
        .UnixArray => input.*.UnixArray = try updated_array.toOwnedSlice(),
        .UUIDArray => input.*.UUIDArray = try updated_array.toOwnedSlice(),
        .BoolArray => input.*.BoolArray = try updated_array.toOwnedSlice(),
        .StrArray => input.*.StrArray = try updated_array.toOwnedSlice(),
        else => unreachable,
    }
}

// I think I could use meta programming here by adding the type as argument
fn append(allocator: std.mem.Allocator, input: *zid.Data, data: ConditionValue) !void {
    var updated_array = std.ArrayList(u8).init(allocator);
    errdefer updated_array.deinit();

    switch (input.*) {
        .IntArray,
        .FloatArray,
        .UnixArray,
        .BoolArray,
        .StrArray,
        .UUIDArray,
        => |v| try updated_array.appendSlice(v),
        else => unreachable,
    }

    var new_len: usize = 0;
    switch (data) {
        .int => |v| {
            try updated_array.appendSlice(std.mem.asBytes(&v));
            new_len = input.size() - 8 + @sizeOf(i32);
        },
        .float => |v| {
            try updated_array.appendSlice(std.mem.asBytes(&v));
            new_len = input.size() - 8 + @sizeOf(f64);
        },
        .unix => |v| {
            try updated_array.appendSlice(std.mem.asBytes(&v));
            new_len = input.size() - 8 + @sizeOf(u64);
        },
        .bool_ => |v| {
            try updated_array.appendSlice(std.mem.asBytes(&v));
            new_len = input.size() - 8 + @sizeOf(bool);
        },
        .str => |v| {
            try updated_array.appendSlice(std.mem.asBytes(&v.len));
            try updated_array.appendSlice(v);
            new_len = input.size() + v.len - 8;
        },
        .int_array => |v| {
            const new_array = try zid.allocEncodArray.Int(allocator, v);
            defer allocator.free(new_array);
            try updated_array.appendSlice(new_array[8..]);
            new_len = input.size() + new_array.len - 16;
        },
        .float_array => |v| {
            const new_array = try zid.allocEncodArray.Float(allocator, v);
            defer allocator.free(new_array);
            try updated_array.appendSlice(new_array[8..]);
            new_len = input.size() + new_array.len - 16;
        },
        .bool_array => |v| {
            const new_array = try zid.allocEncodArray.Bool(allocator, v);
            defer allocator.free(new_array);
            try updated_array.appendSlice(new_array[8..]);
            new_len = input.size() + new_array.len - 16;
        },
        .str_array => |v| {
            const new_array = try zid.allocEncodArray.Str(allocator, v);
            defer allocator.free(new_array);
            try updated_array.appendSlice(new_array[8..]);
            new_len = input.size() + new_array.len - 16;
        },
        .unix_array => |v| {
            const new_array = try zid.allocEncodArray.Unix(allocator, v);
            defer allocator.free(new_array);
            try updated_array.appendSlice(new_array[8..]);
            new_len = input.size() + new_array.len - 16;
        },
        else => unreachable,
    }

    @memcpy(updated_array.items[0..@sizeOf(u64)], std.mem.asBytes(&new_len));

    switch (input.*) {
        .IntArray => input.*.IntArray = try updated_array.toOwnedSlice(),
        .FloatArray => input.*.FloatArray = try updated_array.toOwnedSlice(),
        .UnixArray => input.*.UnixArray = try updated_array.toOwnedSlice(),
        .UUIDArray => input.*.UUIDArray = try updated_array.toOwnedSlice(),
        .BoolArray => input.*.BoolArray = try updated_array.toOwnedSlice(),
        .StrArray => input.*.StrArray = try updated_array.toOwnedSlice(),
        else => unreachable,
    }
}

// TODO: Change the array for a map to speed up thing
// And also I dont really need to realoc anything, only append need because here it can only go lower
// So I could just memcopy the remaining of the bytes at the current position, so it overwrite the value to remove
// Like if I want to re;ove 3 in [1 2 3 4 5], it would become [1 2 4 5 5]. Then I dont take the last value when I return.
// But that mean I keep in memory useless data, so maybe not
fn remove(allocator: std.mem.Allocator, input: *zid.Data, data: ConditionValue) !void {
    var iter = try zid.ArrayIterator.init(input.*);
    switch (input.*) {
        .IntArray => {
            var array = std.ArrayList(i32).init(allocator);
            defer array.deinit();
            while (iter.next()) |v| if (!in(v, data)) try array.append(v.Int);
            input.*.IntArray = try zid.allocEncodArray.Int(allocator, array.items);
        },
        .FloatArray => {
            var array = std.ArrayList(f64).init(allocator);
            defer array.deinit();
            while (iter.next()) |v| if (!in(v, data)) try array.append(v.Float);
            input.*.FloatArray = try zid.allocEncodArray.Float(allocator, array.items);
        },
        .UnixArray => {
            var array = std.ArrayList(u64).init(allocator);
            defer array.deinit();
            while (iter.next()) |v| if (!in(v, data)) try array.append(v.Unix);
            input.*.UnixArray = try zid.allocEncodArray.Unix(allocator, array.items);
        },
        .BoolArray => {
            var array = std.ArrayList(bool).init(allocator);
            defer array.deinit();
            while (iter.next()) |v| if (!in(v, data)) try array.append(v.Bool);
            input.*.BoolArray = try zid.allocEncodArray.Bool(allocator, array.items);
        },
        .StrArray => {
            var array = std.ArrayList([]const u8).init(allocator);
            defer array.deinit();
            while (iter.next()) |v| if (!in(v, data)) try array.append(v.Str);
            input.*.StrArray = try zid.allocEncodArray.Str(allocator, array.items);
        },
        .UUIDArray => {
            var array = std.ArrayList([16]u8).init(allocator);
            defer array.deinit();
            while (iter.next()) |v| if (!in(v, data)) try array.append(v.UUID);
            input.*.UUIDArray = try zid.allocEncodArray.UUID(allocator, array.items);
        },
        else => unreachable,
    }
}

fn removeat(allocator: std.mem.Allocator, input: *zid.Data, data: ConditionValue) !void {
    var iter = try zid.ArrayIterator.init(input.*);
    switch (input.*) {
        .IntArray => {
            var array = std.ArrayList(i32).init(allocator);
            defer array.deinit();
            var i: i32 = 0; // Maybe use usize because here it limite the size of the array
            while (iter.next()) |v| {
                defer i += 1;
                if (!in(zid.Data{ .Int = i }, data)) try array.append(v.Int);
            }
            input.*.IntArray = try zid.allocEncodArray.Int(allocator, array.items);
        },
        .FloatArray => {
            var array = std.ArrayList(f64).init(allocator);
            defer array.deinit();
            var i: i32 = 0; // Maybe use usize because here it limite the size of the array
            while (iter.next()) |v| {
                defer i += 1;
                if (!in(zid.Data{ .Int = i }, data)) try array.append(v.Float);
            }
            input.*.FloatArray = try zid.allocEncodArray.Float(allocator, array.items);
        },
        .UnixArray => {
            var array = std.ArrayList(u64).init(allocator);
            defer array.deinit();
            var i: i32 = 0; // Maybe use usize because here it limite the size of the array
            while (iter.next()) |v| {
                defer i += 1;
                if (!in(zid.Data{ .Int = i }, data)) try array.append(v.Unix);
            }
            input.*.UnixArray = try zid.allocEncodArray.Unix(allocator, array.items);
        },
        .BoolArray => {
            var array = std.ArrayList(bool).init(allocator);
            defer array.deinit();
            var i: i32 = 0; // Maybe use usize because here it limite the size of the array
            while (iter.next()) |v| {
                defer i += 1;
                if (!in(zid.Data{ .Int = i }, data)) try array.append(v.Bool);
            }
            input.*.BoolArray = try zid.allocEncodArray.Bool(allocator, array.items);
        },
        .StrArray => {
            var array = std.ArrayList([]const u8).init(allocator);
            defer array.deinit();
            var i: i32 = 0; // Maybe use usize because here it limite the size of the array
            while (iter.next()) |v| {
                defer i += 1;
                if (!in(zid.Data{ .Int = i }, data)) try array.append(v.Str);
            }
            input.*.StrArray = try zid.allocEncodArray.Str(allocator, array.items);
        },
        .UUIDArray => unreachable, // I cant do that for removeat because link don't really have order
        else => unreachable,
    }
}

// TODO: Use a map.contain for the ConditionValue
// Specially because I end up iterate over the list for all entity, when I just need to make the map one time for all
fn in(x: zid.Data, y: ConditionValue) bool {
    switch (x) {
        .Int => |v| for (y.int_array) |z| if (v == z) return true,
        .Float => |v| for (y.float_array) |z| if (v == z) return true,
        .Unix => |v| for (y.unix_array) |z| if (v == z) return true,
        .Bool => |v| for (y.bool_array) |z| if (v == z) return true,
        .Str => |v| for (y.str_array) |z| if (std.mem.eql(u8, z, v)) return true,
        .UUID => |v| if (y.link_array.contains(dtype.UUID{ .bytes = v })) return true,
        else => unreachable,
    }
    return false;
}
