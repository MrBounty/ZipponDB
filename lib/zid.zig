const std = @import("std");

// Maybe make buffer infinite with arrayList, but this is faster I think
// Maybe give the option ? Like 2 kind of reader ? One with an arrayList as arg
// I like this, I think I will do it. But later, at least I can see a way to keep the same API and use ArrayList as main buffer

const STRING_BUFFER_LENGTH = 1024 * 64 * 64; // Around 4.2Mbyte
var string_buffer: [STRING_BUFFER_LENGTH]u8 = undefined;

const ARRAY_BUFFER_LENGTH = 1024 * 64 * 64; // Around 4.2Mbyte
var array_buffer: [ARRAY_BUFFER_LENGTH]u8 = undefined;

pub const DType = enum {
    Int,
    Float,
    Str,
    Bool,
    UUID,
    Unix,

    IntArray,
    FloatArray,
    StrArray,
    BoolArray,
    UUIDArray,
    UnixArray,

    // I dont really like that there is a sperate function but ok
    // I had to do that so I can pass a second argument
    fn readStr(_: DType, reader: anytype, str_index: *usize) !Data {
        // Read the length of the string
        var len_buffer: [4]u8 = undefined;
        _ = try reader.readAtLeast(len_buffer[0..], @sizeOf(u32));
        const len = @as(usize, @intCast(std.mem.bytesToValue(u32, &len_buffer)));

        const end = str_index.* + len;
        if (end > string_buffer.len) return error.BufferFull;

        // Read the string
        _ = try reader.readAtLeast(string_buffer[str_index.*..end], len);
        const data = Data{ .Str = string_buffer[str_index.*..end] };

        str_index.* += len;
        return data;
    }

    fn readArray(self: DType, reader: anytype, array_index: *usize) !Data {
        // First 8 byte of an array is the number of u8 that take this array
        // This speed up the reading and allow str array easely
        var len_buffer: [8]u8 = undefined;
        _ = try reader.readAtLeast(len_buffer[0..], @sizeOf(u64));
        const len = @as(usize, @intCast(std.mem.bytesToValue(u64, &len_buffer)));

        // Get the end of the slice use in the array buffer and check if not too long
        const origin = array_index.*;
        const start = array_index.* + @sizeOf(u64);
        const end = start + len;
        if (end > array_buffer.len) return error.BufferFull;

        // Copy the len of the array and read all value
        @memcpy(array_buffer[array_index.*..start], len_buffer[0..]);
        _ = try reader.readAtLeast(array_buffer[start..end], len);
        array_index.* = end;

        return switch (self) {
            .IntArray => Data{ .IntArray = array_buffer[origin..end] },
            .FloatArray => Data{ .FloatArray = array_buffer[origin..end] },
            .BoolArray => Data{ .BoolArray = array_buffer[origin..end] },
            .UUIDArray => Data{ .UUIDArray = array_buffer[origin..end] },
            .UnixArray => Data{ .UnixArray = array_buffer[origin..end] },
            .StrArray => Data{ .StrArray = array_buffer[origin..end] },
            else => unreachable,
        };
    }

    fn read(self: DType, reader: anytype) !Data {
        switch (self) {
            .Int => {
                var buffer: [@sizeOf(i32)]u8 = undefined;
                _ = try reader.readAtLeast(buffer[0..], @sizeOf(i32));
                return Data{ .Int = std.mem.bytesToValue(i32, &buffer) };
            },
            .Float => {
                var buffer: [@sizeOf(f64)]u8 = undefined;
                _ = try reader.readAtLeast(buffer[0..], @sizeOf(f64));
                return Data{ .Float = std.mem.bytesToValue(f64, &buffer) };
            },
            .Bool => {
                var buffer: [@sizeOf(bool)]u8 = undefined;
                _ = try reader.readAtLeast(buffer[0..], @sizeOf(bool));
                return Data{ .Bool = std.mem.bytesToValue(bool, &buffer) };
            },
            .UUID => {
                var buffer: [@sizeOf([16]u8)]u8 = undefined;
                _ = try reader.readAtLeast(buffer[0..], @sizeOf([16]u8));
                return Data{ .UUID = std.mem.bytesToValue([16]u8, &buffer) };
            },
            .Unix => {
                var buffer: [@sizeOf(u64)]u8 = undefined;
                _ = try reader.readAtLeast(buffer[0..], @sizeOf(u64));
                return Data{ .Unix = std.mem.bytesToValue(u64, &buffer) };
            },
            else => unreachable,
        }
    }
};

pub const Data = union(DType) {
    Int: i32,
    Float: f64,
    Str: []const u8,
    Bool: bool,
    UUID: [16]u8,
    Unix: u64,

    IntArray: []const u8,
    FloatArray: []const u8,
    StrArray: []const u8,
    BoolArray: []const u8,
    UUIDArray: []const u8,
    UnixArray: []const u8,

    /// Number of bytes that will be use in the file
    pub fn size(self: Data) usize {
        return switch (self) {
            .Int => @sizeOf(i32),
            .Float => @sizeOf(f64),
            .Str => 4 + self.Str.len,
            .Bool => @sizeOf(bool),
            .UUID => @sizeOf([16]u8),
            .Unix => @sizeOf(u64),

            .IntArray => self.IntArray.len,
            .FloatArray => self.FloatArray.len,
            .StrArray => self.StrArray.len,
            .BoolArray => self.BoolArray.len,
            .UUIDArray => self.UUIDArray.len,
            .UnixArray => self.UnixArray.len,
        };
    }

    /// Write the value in bytes
    fn write(self: Data, writer: anytype) !void {
        switch (self) {
            .Str => |v| {
                const len = @as(u32, @intCast(v.len));
                try writer.writeAll(std.mem.asBytes(&len));
                try writer.writeAll(v);
            },
            .UUID => |v| try writer.writeAll(&v),
            .Int => |v| try writer.writeAll(std.mem.asBytes(&v)),
            .Float => |v| try writer.writeAll(std.mem.asBytes(&v)),
            .Bool => |v| try writer.writeAll(std.mem.asBytes(&v)),
            .Unix => |v| try writer.writeAll(std.mem.asBytes(&v)),

            .StrArray => |v| try writer.writeAll(v),
            .UUIDArray => |v| try writer.writeAll(v),
            .IntArray => |v| try writer.writeAll(v),
            .FloatArray => |v| try writer.writeAll(v),
            .BoolArray => |v| try writer.writeAll(v),
            .UnixArray => |v| try writer.writeAll(v),
        }
    }

    pub fn initInt(value: i32) Data {
        return Data{ .Int = value };
    }

    pub fn initFloat(value: f64) Data {
        return Data{ .Float = value };
    }

    pub fn initStr(value: []const u8) Data {
        return Data{ .Str = value };
    }

    pub fn initBool(value: bool) Data {
        return Data{ .Bool = value };
    }

    pub fn initUUID(value: [16]u8) Data {
        return Data{ .UUID = value };
    }

    pub fn initUnix(value: u64) Data {
        return Data{ .Unix = value };
    }

    pub fn initIntArray(value: []const u8) Data {
        return Data{ .IntArray = value };
    }

    pub fn initFloatArray(value: []const u8) Data {
        return Data{ .FloatArray = value };
    }

    pub fn initStrArray(value: []const u8) Data {
        return Data{ .StrArray = value };
    }

    pub fn initBoolArray(value: []const u8) Data {
        return Data{ .BoolArray = value };
    }

    pub fn initUUIDArray(value: []const u8) Data {
        return Data{ .UUIDArray = value };
    }

    pub fn initUnixArray(value: []const u8) Data {
        return Data{ .UnixArray = value };
    }
};

// I know, I know I use @sizeOf too much, but I like it. Allow me to understand what it represent

const empty_buff: [4]u8 = .{ 0, 0, 0, 0 };

/// Take an array of zig type and return an encoded version to use with Data.initType
/// Like that: Data.initIntArray(try allocEncodArray.Int(my_array))
/// Don't forget to free it! allocator.free(data.IntArray)
pub const allocEncodArray = struct {
    pub fn Empty() []const u8 {
        return empty_buff[0..];
    }

    pub fn Int(allocator: std.mem.Allocator, items: []const i32) ![]const u8 {
        const items_len: u64 = items.len * @sizeOf(i32);
        var buffer = try allocator.alloc(u8, @sizeOf(u64) + items_len);

        // Write the first 8 bytes as the number of u8 used to store the array
        @memcpy(buffer[0..@sizeOf(u64)], std.mem.asBytes(&items_len));

        // Write all value in the array
        var start: usize = @sizeOf(u64);
        for (items) |item| {
            const end: usize = start + @sizeOf(i32);
            @memcpy(buffer[start..end], std.mem.asBytes(&item));
            start = end;
        }

        return buffer;
    }

    pub fn Float(allocator: std.mem.Allocator, items: []const f64) ![]const u8 {
        const items_len: u64 = items.len * @sizeOf(f64);
        var buffer = try allocator.alloc(u8, @sizeOf(u64) + items_len);
        @memcpy(buffer[0..@sizeOf(u64)], std.mem.asBytes(&items_len));

        var start: usize = @sizeOf(u64);
        for (items) |item| {
            const end: usize = start + @sizeOf(f64);
            @memcpy(buffer[start..end], std.mem.asBytes(&item));
            start = end;
        }

        return buffer;
    }

    pub fn Bool(allocator: std.mem.Allocator, items: []const bool) ![]const u8 {
        const items_len: u64 = items.len * @sizeOf(bool);
        var buffer = try allocator.alloc(u8, @sizeOf(u64) + items_len);
        @memcpy(buffer[0..@sizeOf(u64)], std.mem.asBytes(&items_len));

        var start: usize = @sizeOf(u64);
        for (items) |item| {
            const end: usize = start + @sizeOf(bool);
            @memcpy(buffer[start..end], std.mem.asBytes(&item));
            start = end;
        }

        return buffer;
    }

    pub fn UUID(allocator: std.mem.Allocator, items: []const [16]u8) ![]const u8 {
        const items_len: u64 = items.len * @sizeOf([16]u8);
        var buffer = try allocator.alloc(u8, @sizeOf(u64) + items_len);
        @memcpy(buffer[0..@sizeOf(u64)], std.mem.asBytes(&items_len));

        var start: usize = @sizeOf(u64);
        for (items) |item| {
            const end: usize = start + @sizeOf([16]u8);
            @memcpy(buffer[start..end], &item);
            start = end;
        }

        return buffer;
    }

    pub fn Unix(allocator: std.mem.Allocator, items: []const u64) ![]const u8 {
        const items_len: u64 = items.len * @sizeOf(u64);
        var buffer = try allocator.alloc(u8, @sizeOf(u64) + items_len);
        @memcpy(buffer[0..@sizeOf(u64)], std.mem.asBytes(&items_len));

        var start: usize = @sizeOf(u64);
        for (items) |item| {
            const end: usize = start + @sizeOf(u64);
            @memcpy(buffer[start..end], std.mem.asBytes(&item));
            start = end;
        }

        return buffer;
    }

    pub fn Str(allocator: std.mem.Allocator, items: []const []const u8) ![]const u8 {
        var total_len: usize = @sizeOf(u64);
        for (items) |item| {
            total_len += @sizeOf(u64) + @sizeOf(u8) * item.len;
        }

        var buffer = try allocator.alloc(u8, total_len);

        // Write the total number of bytes used by this array as the first 8 bytes. Those first 8 are not included
        @memcpy(buffer[0..@sizeOf(u64)], std.mem.asBytes(&(total_len - @sizeOf(u64))));

        // Write the rest, the number of u8 then the array itself, repeat
        var start: usize = @sizeOf(u64);
        var end: usize = 0;
        for (items) |item| {
            // First write the len of the str
            end = start + @sizeOf(u64);
            @memcpy(buffer[start..end], std.mem.asBytes(&item.len));

            end += item.len;
            @memcpy(buffer[(start + @sizeOf(u64))..end], item);
            start = end;
        }

        return buffer;
    }
};

/// This take the name of a file and a schema and return an iterator.
/// You can then use it in a while loop and it will yeild []Data type.
/// One for each write. This is basically like a row in a table.
pub const DataIterator = struct {
    allocator: std.mem.Allocator,
    file: std.fs.File,
    reader: std.io.BufferedReader(4096, std.fs.File.Reader),

    schema: []const DType,
    data: []Data,

    index: usize = 0,
    file_len: usize,
    str_index: usize = 0,
    array_index: usize = 0,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, dir: ?std.fs.Dir, schema: []const DType) !DataIterator {
        const d_ = dir orelse std.fs.cwd();
        const file = try d_.openFile(name, .{ .mode = .read_only });

        return DataIterator{
            .allocator = allocator,
            .file = file,
            .schema = schema,
            .reader = std.io.bufferedReader(file.reader()),
            .data = try allocator.alloc(Data, schema.len),
            .file_len = try file.getEndPos(),
        };
    }

    pub fn deinit(self: *DataIterator) void {
        self.allocator.free(self.data);
        self.file.close();
    }

    pub fn next(self: *DataIterator) !?[]Data {
        self.str_index = 0;
        self.array_index = 0;
        if (self.index >= self.file_len) return null;

        var i: usize = 0;
        while (i < self.schema.len) : (i += 1) {
            self.data[i] = switch (self.schema[i]) {
                .Str => try self.schema[i].readStr(self.reader.reader(), &self.str_index),
                .IntArray,
                .FloatArray,
                .BoolArray,
                .StrArray,
                .UUIDArray,
                .UnixArray,
                => try self.schema[i].readArray(self.reader.reader(), &self.array_index),
                else => try self.schema[i].read(self.reader.reader()),
            };
            self.index += self.data[i].size();
        }

        return self.data;
    }
};

pub const DataIteratorFullBuffer = struct {
    allocator: std.mem.Allocator,
    file: std.fs.File,
    reader: std.io.BufferedReader(4096, std.fs.File.Reader),

    schema: []const DType,
    data: []Data,

    index: usize = 0,
    file_len: usize,
    str_index: usize = 0,
    array_index: usize = 0,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, dir: ?std.fs.Dir, schema: []const DType) !DataIterator {
        const d_ = dir orelse std.fs.cwd();
        const file = try d_.openFile(name, .{ .mode = .read_only });

        return DataIterator{
            .allocator = allocator,
            .file = file,
            .schema = schema,
            .reader = std.io.bufferedReader(file.reader()),
            .data = try allocator.alloc(Data, schema.len),
            .file_len = try file.getEndPos(),
        };
    }

    pub fn deinit(self: *DataIterator) void {
        self.allocator.free(self.data);
        self.file.close();
    }

    pub fn next(self: *DataIterator) !?[]Data {
        self.str_index = 0;
        self.array_index = 0;
        if (self.index >= self.file_len) return null;

        var i: usize = 0;
        while (i < self.schema.len) : (i += 1) {
            self.data[i] = switch (self.schema[i]) {
                .Str => try self.schema[i].readStr(self.reader.reader(), &self.str_index),
                .IntArray,
                .FloatArray,
                .BoolArray,
                .StrArray,
                .UUIDArray,
                .UnixArray,
                => try self.schema[i].readArray(self.reader.reader(), &self.array_index),
                else => try self.schema[i].read(self.reader.reader()),
            };
            self.index += self.data[i].size();
        }

        return self.data;
    }
};

/// When using DataIterator, if one Data is an array (like IntArray). You need to use that to create a sub iterator that return the Data inside the array.
/// This is mainly for performance reason as you only iterate an array if needed, otherwise it is just a big blob of u8, like a str
pub const ArrayIterator = struct {
    data: Data,
    end: usize,
    index: usize,

    pub fn init(data: Data) !ArrayIterator {
        const len = switch (data) {
            .IntArray,
            .FloatArray,
            .BoolArray,
            .StrArray,
            .UUIDArray,
            .UnixArray,
            => |buffer| @as(usize, @intCast(std.mem.bytesToValue(u64, buffer[0..@sizeOf(u64)]))) + @sizeOf(u64),
            else => return error.NonArrayDType,
        };

        return ArrayIterator{
            .data = data,
            .end = len,
            .index = @sizeOf(u64),
        };
    }

    pub fn next(self: *ArrayIterator) ?Data {
        if (self.index >= self.end) return null;

        switch (self.data) {
            .IntArray => |buffer| {
                self.index += @sizeOf(i32);
                return Data{ .Int = std.mem.bytesToValue(i32, buffer[(self.index - @sizeOf(i32))..self.index]) };
            },
            .FloatArray => |buffer| {
                self.index += @sizeOf(f64);
                return Data{ .Float = std.mem.bytesToValue(f64, buffer[(self.index - @sizeOf(f64))..self.index]) };
            },
            .BoolArray => |buffer| {
                self.index += @sizeOf(bool);
                return Data{ .Bool = std.mem.bytesToValue(bool, buffer[(self.index - @sizeOf(bool))..self.index]) };
            },
            .UUIDArray => |buffer| {
                self.index += @sizeOf([16]u8);
                return Data{ .UUID = std.mem.bytesToValue([16]u8, buffer[(self.index - @sizeOf([16]u8))..self.index]) };
            },
            .UnixArray => |buffer| {
                self.index += @sizeOf(u64);
                return Data{ .Unix = std.mem.bytesToValue(u64, buffer[(self.index - @sizeOf(u64))..self.index]) };
            },
            .StrArray => |buffer| {
                // Read first 8 bytes as len, copy it into the buffer then return the slice
                const len = @as(usize, @intCast(std.mem.bytesToValue(u64, buffer[self.index..(self.index + @sizeOf(u64))])));
                self.index += @sizeOf(u64) + len;
                return Data{ .Str = buffer[(self.index - len)..self.index] };
            },
            else => unreachable,
        }
    }
};

/// A data writer to write into a file. I use a struct so I can use a buffer and improve perf
/// I added a seperated flush method, to not flush at each write. Otherwise it is very long
/// Performance concern once again.
pub const DataWriter = struct {
    file: std.fs.File,
    writer: std.io.BufferedWriter(4096, std.fs.File.Writer),

    pub fn init(name: []const u8, dir: ?std.fs.Dir) !DataWriter {
        const d_ = dir orelse std.fs.cwd();
        const file = try d_.openFile(name, .{ .mode = .write_only });
        try file.seekFromEnd(0);

        return DataWriter{
            .file = file,
            .writer = std.io.bufferedWriter(file.writer()),
        };
    }

    pub fn deinit(self: *DataWriter) void {
        self.file.close();
    }

    pub fn write(self: *DataWriter, data: []const Data) !void {
        const writer = self.writer.writer();
        for (data) |d| try d.write(writer);
    }

    pub fn flush(self: *DataWriter) !void {
        try self.writer.flush();
    }

    pub fn fileStat(self: DataWriter) !std.fs.File.Stat {
        return self.file.stat();
    }
};

/// Create a new data file that can then be use by the DataWriter
pub fn createFile(name: []const u8, dir: ?std.fs.Dir) !void {
    const d = dir orelse std.fs.cwd();
    const file = try d.createFile(name, .{});
    defer file.close();
}

/// Self explainatory.
pub fn deleteFile(name: []const u8, dir: ?std.fs.Dir) !void {
    const d = dir orelse std.fs.cwd();
    try d.deleteFile(name);
}

/// Just to keep a similar API
pub fn statFile(name: []const u8, dir: ?std.fs.Dir) !std.fs.File.Stat {
    const d = dir orelse std.fs.cwd();
    return d.statFile(name);
}

// I have almost more lines of test than the real stuff x)
// But I think everything is tested to be fair, so good stuff
// It also write benchmark so you can benchmark on your own hardware
// The data write and read is not really representative of real world tho

test "Array Iterators" {
    const allocator = std.testing.allocator;

    try std.fs.cwd().makeDir("array_tmp");
    var dir = try std.fs.cwd().openDir("array_tmp", .{});
    defer {
        dir.close();
        std.fs.cwd().deleteDir("array_tmp") catch {};
    }

    // Test data
    const int_array = [_]i32{ 32, 11, 15, 99 };
    const float_array = [_]f64{ 3.14, 2.718, 1.414, 0.577 };
    const bool_array = [_]bool{ true, false, true, false };
    const uuid_array = [_][16]u8{
        [_]u8{0} ** 16,
        [_]u8{1} ** 16,
        [_]u8{2} ** 16,
        [_]u8{3} ** 16,
    };
    const unix_array = [_]u64{ 1623456789, 1623456790, 1623456791, 1623456792 };
    const str_array = [_][]const u8{ "Hello", " world" };

    const data = [_]Data{
        Data.initIntArray(try allocEncodArray.Int(allocator, &int_array)),
        Data.initFloatArray(try allocEncodArray.Float(allocator, &float_array)),
        Data.initBoolArray(try allocEncodArray.Bool(allocator, &bool_array)),
        Data.initUUIDArray(try allocEncodArray.UUID(allocator, &uuid_array)),
        Data.initUnixArray(try allocEncodArray.Unix(allocator, &unix_array)),
        Data.initStrArray(try allocEncodArray.Str(allocator, &str_array)),
    };
    defer {
        allocator.free(data[0].IntArray);
        allocator.free(data[1].FloatArray);
        allocator.free(data[2].BoolArray);
        allocator.free(data[3].UUIDArray);
        allocator.free(data[4].UnixArray);
        allocator.free(data[5].StrArray);
    }

    // Write data to file
    try createFile("test_arrays", dir);
    var dwriter = try DataWriter.init("test_arrays", dir);
    defer dwriter.deinit();
    try dwriter.write(&data);
    try dwriter.flush();

    // Read and verify data
    const schema = &[_]DType{ .IntArray, .FloatArray, .BoolArray, .UUIDArray, .UnixArray, .StrArray };
    var iter = try DataIterator.init(allocator, "test_arrays", dir, schema);
    defer iter.deinit();

    if (try iter.next()) |row| {
        // Int Array
        {
            var array_iter = try ArrayIterator.init(row[0]);
            var i: usize = 0;
            while (array_iter.next()) |d| {
                try std.testing.expectEqual(int_array[i], d.Int);
                i += 1;
            }
            try std.testing.expectEqual(int_array.len, i);
        }

        // Float Array
        {
            var array_iter = try ArrayIterator.init(row[1]);
            var i: usize = 0;
            while (array_iter.next()) |d| {
                try std.testing.expectApproxEqAbs(float_array[i], d.Float, 0.0001);
                i += 1;
            }
            try std.testing.expectEqual(float_array.len, i);
        }

        // Bool Array
        {
            var array_iter = try ArrayIterator.init(row[2]);
            var i: usize = 0;
            while (array_iter.next()) |d| {
                try std.testing.expectEqual(bool_array[i], d.Bool);
                i += 1;
            }
            try std.testing.expectEqual(bool_array.len, i);
        }

        // UUID Array
        {
            var array_iter = try ArrayIterator.init(row[3]);
            var i: usize = 0;
            while (array_iter.next()) |d| {
                try std.testing.expectEqualSlices(u8, &uuid_array[i], &d.UUID);
                i += 1;
            }
            try std.testing.expectEqual(uuid_array.len, i);
        }

        // Unix Array
        {
            var array_iter = try ArrayIterator.init(row[4]);
            var i: usize = 0;
            while (array_iter.next()) |d| {
                try std.testing.expectEqual(unix_array[i], d.Unix);
                i += 1;
            }
            try std.testing.expectEqual(unix_array.len, i);
        }

        // Str Array
        {
            var array_iter = try ArrayIterator.init(row[5]);
            var i: usize = 0;
            while (array_iter.next()) |d| {
                try std.testing.expectEqualStrings(str_array[i], d.Str);
                i += 1;
            }
            try std.testing.expectEqual(str_array.len, i);
        }
    } else {
        return error.TestUnexpectedNull;
    }

    try deleteFile("test_arrays", dir);
}

test "Write and Read" {
    const allocator = std.testing.allocator;

    try std.fs.cwd().makeDir("tmp");
    const dir = try std.fs.cwd().openDir("tmp", .{});

    const data = [_]Data{
        Data.initInt(1),
        Data.initFloat(3.14159),
        Data.initInt(-5),
        Data.initStr("Hello world"),
        Data.initBool(true),
        Data.initUnix(12476),
        Data.initStr("Another string =)"),
    };

    try createFile("test", dir);

    var dwriter = try DataWriter.init("test", dir);
    defer dwriter.deinit();
    try dwriter.write(&data);
    try dwriter.flush();

    const schema = &[_]DType{
        .Int,
        .Float,
        .Int,
        .Str,
        .Bool,
        .Unix,
        .Str,
    };
    var iter = try DataIterator.init(allocator, "test", dir, schema);
    defer iter.deinit();

    if (try iter.next()) |row| {
        try std.testing.expectEqual(1, row[0].Int);
        try std.testing.expectApproxEqAbs(3.14159, row[1].Float, 0.00001);
        try std.testing.expectEqual(-5, row[2].Int);
        try std.testing.expectEqualStrings("Hello world", row[3].Str);
        try std.testing.expectEqual(true, row[4].Bool);
        try std.testing.expectEqual(12476, row[5].Unix);
        try std.testing.expectEqualStrings("Another string =)", row[6].Str);
    } else {
        return error.TestUnexpectedNull;
    }

    try deleteFile("test", dir);
    try std.fs.cwd().deleteDir("tmp");
}

test "Benchmark Write and Read All" {
    const schema = &[_]DType{
        .Int,
        .Float,
        .Int,
        .Str,
        .Bool,
        .Unix,
    };

    const data = &[_]Data{
        Data.initInt(1),
        Data.initFloat(3.14159),
        Data.initInt(-5),
        Data.initStr("Hello world"),
        Data.initBool(true),
        Data.initUnix(2021),
    };

    try benchmark(schema, data);
}

test "Benchmark Write and Read Simple User" {
    const schema = &[_]DType{
        .Int,
        .Str,
    };

    const data = &[_]Data{
        Data.initInt(1),
        Data.initStr("Bob"),
    };

    try benchmark(schema, data);
}

fn benchmark(schema: []const DType, data: []const Data) !void {
    const allocator = std.testing.allocator;
    const sizes = [_]usize{ 1, 10, 100, 1_000, 10_000, 100_000, 1_000_000 };

    try std.fs.cwd().makeDir("benchmark_tmp");
    const dir = try std.fs.cwd().openDir("benchmark_tmp", .{});
    defer std.fs.cwd().deleteDir("benchmark_tmp") catch {};

    for (sizes) |size| {
        std.debug.print("\nBenchmarking with {d} rows:\n", .{size});

        // Benchmark write
        const write_start = std.time.nanoTimestamp();
        try createFile("benchmark", dir);

        var dwriter = try DataWriter.init("benchmark", dir);
        defer dwriter.deinit();
        for (0..size) |_| try dwriter.write(data);
        try dwriter.flush();
        const write_end = std.time.nanoTimestamp();
        const write_duration = @as(f64, @floatFromInt(write_end - write_start)) / 1e6;

        std.debug.print("Write time: {d:.6} ms\n", .{write_duration});
        std.debug.print("Average write time: {d:.2} μs\n", .{write_duration / @as(f64, @floatFromInt(size)) * 1000});

        // Benchmark read
        const read_start = std.time.nanoTimestamp();
        var iter = try DataIterator.init(allocator, "benchmark", dir, schema);
        defer iter.deinit();

        var count: usize = 0;
        while (try iter.next()) |_| {
            count += 1;
        }
        const read_end = std.time.nanoTimestamp();
        const read_duration = @as(f64, @floatFromInt(read_end - read_start)) / 1e6;

        std.debug.print("Read time: {d:.6} ms\n", .{read_duration});
        std.debug.print("Average read time: {d:.2} μs\n", .{read_duration / @as(f64, @floatFromInt(size)) * 1000});
        try std.testing.expectEqual(size, count);

        std.debug.print("{any}", .{statFile("benchmark", dir)});

        try deleteFile("benchmark", dir);
        std.debug.print("\n", .{});
    }
}

test "Benchmark Type" {
    const random = std.crypto.random;
    const uuid = [16]u8{
        random.int(u8),
        random.int(u8),
        random.int(u8),
        random.int(u8),
        random.int(u8),
        random.int(u8),
        random.int(u8),
        random.int(u8),
        random.int(u8),
        random.int(u8),
        random.int(u8),
        random.int(u8),
        random.int(u8),
        random.int(u8),
        random.int(u8),
        random.int(u8),
    };

    try benchmarkType(.Int, Data.initInt(random.int(i32)));
    try benchmarkType(.Float, Data.initFloat(random.float(f64)));
    try benchmarkType(.Bool, Data.initBool(random.boolean()));
    try benchmarkType(.Str, Data.initStr("Hello world"));
    try benchmarkType(.UUID, Data.initUUID(uuid));
    try benchmarkType(.Unix, Data.initUnix(random.int(u64)));
}

fn benchmarkType(dtype: DType, data: Data) !void {
    const allocator = std.testing.allocator;

    const size = 1_000_000;

    try std.fs.cwd().makeDir("benchmark_type_tmp");
    const dir = try std.fs.cwd().openDir("benchmark_type_tmp", .{});
    defer std.fs.cwd().deleteDir("benchmark_type_tmp") catch {};

    std.debug.print("\nBenchmarking with {any} rows:\n", .{dtype});

    // Benchmark write
    const write_start = std.time.nanoTimestamp();
    try createFile("benchmark", dir);

    const datas = &[_]Data{data};

    var dwriter = try DataWriter.init("benchmark", dir);
    defer dwriter.deinit();
    for (0..size) |_| try dwriter.write(datas);
    try dwriter.flush();
    const write_end = std.time.nanoTimestamp();
    const write_duration = @as(f64, @floatFromInt(write_end - write_start)) / 1e6;

    std.debug.print("Write time: {d:.6} ms\n", .{write_duration});

    const schema = &[_]DType{dtype};

    // Benchmark read
    const read_start = std.time.nanoTimestamp();
    var iter = try DataIterator.init(allocator, "benchmark", dir, schema);
    defer iter.deinit();

    var count: usize = 0;
    while (try iter.next()) |_| {
        count += 1;
    }
    const read_end = std.time.nanoTimestamp();
    const read_duration = @as(f64, @floatFromInt(read_end - read_start)) / 1e6;

    std.debug.print("Read time: {d:.6} ms\n", .{read_duration});
    try std.testing.expectEqual(size, count);

    std.debug.print("{any}", .{statFile("benchmark", dir)});

    try deleteFile("benchmark", dir);
    std.debug.print("\n", .{});
}
