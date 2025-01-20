const std = @import("std");
const zid = @import("ZipponData");
const dtype = @import("dtype");
const ConditionValue = @import("../dataStructure/filter.zig").ConditionValue;
const ArrayCondition = @import("../ziql/parts//newData.zig").ArrayCondition;

pub fn updateData(allocator: std.mem.Allocator, condition: ArrayCondition, input: *zid.Data, data: []ConditionValue) !void {
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

fn allocForAppend(allocator: std.mem.Allocator, input: *zid.Data, data: []ConditionValue) []zid.Data {
    switch (input.*) {
        .UUIDArray => {
            var total: usize = 0;
            for (data) |d| total += d.link_array.count();
            return try allocator.alloc(zid.Data, total);
        },
        else => return try allocator.alloc(zid.Data, data.len),
    }
}
// I think I could use meta programming here by adding the type as argument
fn append(allocator: std.mem.Allocator, input: *zid.Data, data: []ConditionValue) !void {
    switch (input.*) {
        .IntArray => {
            // 1. Make a list of the right type from ConditionValue
            var array = std.ArrayList(i32).init(allocator);
            defer array.deinit();
            for (data) |d| try array.append(d.int);

            // 2. Encode the new array
            const new_array = try zid.allocEncodArray.Int(allocator, array.items);

            // 3. Add the new array at the end of the old one without the first 4 bytes that are the number of value in the array
            var updated_array = std.ArrayList(u8).init(allocator);
            try updated_array.appendSlice(input.IntArray);
            try updated_array.appendSlice(new_array[4..]);

            // 4. Update the number of value in the array
            const new_len = input.size() + data.len;
            @memcpy(updated_array.items[0..@sizeOf(u64)], std.mem.asBytes(&new_len));

            // 5. Update the input
            input.*.IntArray = try updated_array.toOwnedSlice();
        },
        .FloatArray => {
            var array = std.ArrayList(f64).init(allocator);
            defer array.deinit();
            for (data) |d| try array.append(d.float);
            const new_array = try zid.allocEncodArray.Float(allocator, array.items);
            var updated_array = std.ArrayList(u8).init(allocator);
            try updated_array.appendSlice(input.FloatArray);
            try updated_array.appendSlice(new_array[4..]);
            const new_len = input.size() + data.len;
            @memcpy(updated_array.items[0..@sizeOf(u64)], std.mem.asBytes(&new_len));
            input.*.FloatArray = try updated_array.toOwnedSlice();
        },
        .UnixArray => {
            var array = std.ArrayList(u64).init(allocator);
            defer array.deinit();
            for (data) |d| try array.append(d.unix);
            const new_array = try zid.allocEncodArray.Unix(allocator, array.items);
            var updated_array = std.ArrayList(u8).init(allocator);
            try updated_array.appendSlice(input.UnixArray);
            try updated_array.appendSlice(new_array[4..]);
            const new_len = input.size() + data.len;
            @memcpy(updated_array.items[0..@sizeOf(u64)], std.mem.asBytes(&new_len));
            input.*.UnixArray = try updated_array.toOwnedSlice();
        },
        .BoolArray => {
            var array = std.ArrayList(bool).init(allocator);
            defer array.deinit();
            for (data) |d| try array.append(d.bool_);
            const new_array = try zid.allocEncodArray.Bool(allocator, array.items);
            var updated_array = std.ArrayList(u8).init(allocator);
            try updated_array.appendSlice(input.BoolArray);
            try updated_array.appendSlice(new_array[4..]);
            const new_len = input.size() + data.len;
            @memcpy(updated_array.items[0..@sizeOf(u64)], std.mem.asBytes(&new_len));
            input.*.BoolArray = try updated_array.toOwnedSlice();
        },
        .StrArray => {
            var array = std.ArrayList([]const u8).init(allocator);
            defer array.deinit();
            for (data) |d| try array.append(d.str);
            const new_array = try zid.allocEncodArray.Str(allocator, array.items);
            var updated_array = std.ArrayList(u8).init(allocator);
            try updated_array.appendSlice(input.StrArray);
            try updated_array.appendSlice(new_array[4..]);
            const new_len = input.size() + data.len;
            @memcpy(updated_array.items[0..@sizeOf(u64)], std.mem.asBytes(&new_len));
            input.*.StrArray = try updated_array.toOwnedSlice();
        },
        .UUIDArray => { // If input is a UUID array, that mean all data are also UUIDArray. There should be only one UUIDArray in data as it is use like that "friends APPEND {name = 'Bob'}"
            var array = std.ArrayList([16]u8).init(allocator);
            defer array.deinit();
            for (data) |d| {
                var iter = d.link_array.keyIterator();
                while (iter.next()) |uuid| try array.append(uuid.bytes);
            }
            const new_array = try zid.allocEncodArray.UUID(allocator, array.items);
            var updated_array = std.ArrayList(u8).init(allocator);
            try updated_array.appendSlice(input.UUIDArray);
            try updated_array.appendSlice(new_array[4..]);
            const new_len = input.size() + array.items.len;
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
fn remove(allocator: std.mem.Allocator, input: *zid.Data, data: []ConditionValue) !void {
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

fn removeat(allocator: std.mem.Allocator, input: *zid.Data, data: []ConditionValue) !void {
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

// Should just use a map.contain
fn in(x: zid.Data, y: []ConditionValue) bool {
    switch (x) {
        .Int => |v| for (y) |z| if (v == z.int) return true,
        .Float => |v| for (y) |z| if (v == z.float) return true,
        .Unix => |v| for (y) |z| if (v == z.unix) return true,
        .Bool => |v| for (y) |z| if (v == z.bool_) return true,
        .Str => |v| for (y) |z| if (std.mem.eql(u8, z.str, v)) return true,
        .UUID => |v| for (y) |z| if (z.link_array.contains(dtype.UUID{ .bytes = v })) return true,
        else => unreachable,
    }
    return false;
}
