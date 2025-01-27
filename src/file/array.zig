const std = @import("std");
const zid = @import("ZipponData");
const dtype = @import("dtype");
const ConditionValue = @import("../dataStructure/filter.zig").ConditionValue;
const ArrayCondition = @import("../ziql/parts//newData.zig").ArrayCondition;

// This shouldn't be here, to move somewhere, idk yet

/// Update an array based on keyword like append or remove
pub fn updateData(allocator: std.mem.Allocator, condition: ArrayCondition, input: *zid.Data, data: ConditionValue) !void {
    switch (condition) {
        .append => try append(allocator, input, data),
        .pop => pop(input),
        .clear => clear(input),
        .remove => try remove(allocator, input, data),
        .removeat => try removeat(allocator, input, data),
    }
}

fn pop(input: *zid.Data) void {
    switch (input.*) {
        .IntArray => |v| if (v.len > 4) {
            input.*.IntArray = v[0 .. v.len - input.size()];
        },
        .FloatArray => |v| if (v.len > 4) {
            input.*.FloatArray = v[0 .. v.len - input.size()];
        },
        .UnixArray => |v| if (v.len > 4) {
            input.*.UnixArray = v[0 .. v.len - input.size()];
        },
        .UUIDArray => |v| if (v.len > 4) {
            input.*.UUIDArray = v[0 .. v.len - input.size()];
        },
        .BoolArray => |v| if (v.len > 4) {
            input.*.BoolArray = v[0 .. v.len - input.size()];
        },
        .StrArray => |v| if (v.len > 4) {
            input.*.StrArray = v[0 .. v.len - input.size()];
        },
        else => unreachable,
    }
}

fn clear(input: *zid.Data) void {
    switch (input.*) {
        .IntArray => input.*.IntArray = zid.allocEncodArray.Empty(),
        .FloatArray => input.*.FloatArray = zid.allocEncodArray.Empty(),
        .UnixArray => input.*.UnixArray = zid.allocEncodArray.Empty(),
        .UUIDArray => input.*.UUIDArray = zid.allocEncodArray.Empty(),
        .BoolArray => input.*.BoolArray = zid.allocEncodArray.Empty(),
        .StrArray => input.*.StrArray = zid.allocEncodArray.Empty(),
        else => unreachable,
    }
}

// I think I could use meta programming here by adding the type as argument
// TODO: Update the remaining type like int
fn append(allocator: std.mem.Allocator, input: *zid.Data, data: ConditionValue) !void {
    switch (input.*) {
        .IntArray => {
            var updated_array = std.ArrayList(u8).init(allocator);
            try updated_array.appendSlice(input.IntArray);

            switch (data) {
                .int => |v| {
                    try updated_array.appendSlice(std.mem.asBytes(&v));
                    const new_len = input.size() - 8 + @sizeOf(i32);
                    @memcpy(updated_array.items[0..@sizeOf(u64)], std.mem.asBytes(&new_len));
                },
                .int_array => |v| {
                    const new_array = try zid.allocEncodArray.Int(allocator, v);
                    try updated_array.appendSlice(new_array[8..]);

                    const new_len = input.size() + new_array.len - 16;
                    @memcpy(updated_array.items[0..@sizeOf(u64)], std.mem.asBytes(&new_len));
                },
                else => unreachable,
            }

            input.*.IntArray = try updated_array.toOwnedSlice();
        },
        .FloatArray => {
            var array = std.ArrayList(f64).init(allocator);
            defer array.deinit();
            try array.appendSlice(data.float_array);
            const new_array = try zid.allocEncodArray.Float(allocator, array.items);
            var updated_array = std.ArrayList(u8).init(allocator);
            try updated_array.appendSlice(input.FloatArray);
            try updated_array.appendSlice(new_array[8..]);
            const new_len = input.size() + new_array.len - 16;
            @memcpy(updated_array.items[0..@sizeOf(u64)], std.mem.asBytes(&new_len));
            input.*.FloatArray = try updated_array.toOwnedSlice();
        },
        .UnixArray => {
            var array = std.ArrayList(u64).init(allocator);
            defer array.deinit();
            try array.appendSlice(data.unix_array);
            const new_array = try zid.allocEncodArray.Unix(allocator, array.items);
            var updated_array = std.ArrayList(u8).init(allocator);
            try updated_array.appendSlice(input.UnixArray);
            try updated_array.appendSlice(new_array[8..]);
            const new_len = input.size() + new_array.len - 16;
            @memcpy(updated_array.items[0..@sizeOf(u64)], std.mem.asBytes(&new_len));
            input.*.UnixArray = try updated_array.toOwnedSlice();
        },
        .BoolArray => {
            var array = std.ArrayList(bool).init(allocator);
            defer array.deinit();
            try array.appendSlice(data.bool_array);
            const new_array = try zid.allocEncodArray.Bool(allocator, array.items);
            var updated_array = std.ArrayList(u8).init(allocator);
            try updated_array.appendSlice(input.BoolArray);
            try updated_array.appendSlice(new_array[8..]);
            const new_len = input.size() + new_array.len - 16;
            @memcpy(updated_array.items[0..@sizeOf(u64)], std.mem.asBytes(&new_len));
            input.*.BoolArray = try updated_array.toOwnedSlice();
        },
        .StrArray => {
            var array = std.ArrayList([]const u8).init(allocator);
            defer array.deinit();
            try array.appendSlice(data.str_array);
            const new_array = try zid.allocEncodArray.Str(allocator, array.items);
            var updated_array = std.ArrayList(u8).init(allocator);
            try updated_array.appendSlice(input.StrArray);
            try updated_array.appendSlice(new_array[8..]);
            const new_len = input.size() + new_array.len - 16;
            @memcpy(updated_array.items[0..@sizeOf(u64)], std.mem.asBytes(&new_len));
            input.*.StrArray = try updated_array.toOwnedSlice();
        },
        .UUIDArray => { // If input is a UUID array, that mean all data are also UUIDArray
            var array = std.ArrayList([16]u8).init(allocator);
            defer array.deinit();

            var iter = data.link_array.keyIterator();
            while (iter.next()) |uuid| try array.append(uuid.bytes);
            const new_array = try zid.allocEncodArray.UUID(allocator, array.items);

            var updated_array = std.ArrayList(u8).init(allocator);
            try updated_array.appendSlice(input.UUIDArray);
            try updated_array.appendSlice(new_array[8..]);

            const new_len = input.size() + new_array.len - 16;
            @memcpy(updated_array.items[0..@sizeOf(u64)], std.mem.asBytes(&new_len));
            input.*.UUIDArray = try updated_array.toOwnedSlice();
        },
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
