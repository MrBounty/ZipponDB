# ZipponData

ZipponData is a library developped in the context of [ZipponDB](https://github.com/MrBounty/ZipponDB/tree/v0.1.3).

The library intent to create a simple way to store and parse data from a file in the most efficient and fast way possible. 

There is 6 data type available in ZipponData:

| Type | Zig type | Bytes in file |
| --- | --- | --- |
| int | i32 | 4 |
| float | f64 | 8 |
| bool | bool | 1 |
| str | []u8 | 4 + len |
| uuid | [16]u8 | 16 |
| unix | u64 | 8 |

Each type have its array equivalent.

## Quickstart

1. Create a file with `createFile`
2. Create some `Data`
3. Create a `DataWriter`
4. Write the data
5. Create a schema
6. Create an iterator with `DataIterator`
7. Iterate over all value
8. Delete the file with `deleteFile`

Here an example of how to use it:
``` zig
const std = @import("std");

pub fn main() !void {
    const allocator = std.testing.allocator;

    // 0. Make a temporary directory
    try std.fs.cwd().makeDir("tmp");
    const dir = try std.fs.cwd().openDir("tmp", .{});

    // 1. Create a file
    try createFile("test", dir);

    // 2. Create some Data
    const data = [_]Data{
        Data.initInt(1),
        Data.initFloat(3.14159),
        Data.initInt(-5),
        Data.initStr("Hello world"),
        Data.initBool(true),
        Data.initUnix(2021),
    };

    // 3. Create a DataWriter
    var dwriter = try DataWriter.init("test", dir);
    defer dwriter.deinit(); // This just close the file

    // 4. Write some data
    try dwriter.write(&data);
    try dwriter.write(&data);
    try dwriter.write(&data);
    try dwriter.write(&data);
    try dwriter.write(&data);
    try dwriter.write(&data);
    try dwriter.flush(); // Dont forget to flush !

    // 5. Create a schema
    // A schema is how  the iterator will parse the file. 
    // If you are wrong here, it will return wrong/random data
    // And most likely an error when iterating in the while loop
    const schema = &[_]DType{
        .Int,
        .Float,
        .Int,
        .Str,
        .Bool,
        .Unix,
    };

    // 6. Create a DataIterator
    var iter = try DataIterator.init(allocator, "test", dir, schema);
    defer iter.deinit();

    // 7. Iterate over data
    while (try iter.next()) |row| {
        std.debug.print("Row: {any}\n", .{ row });
    }

    // 8. Delete the file (Optional ofc)
    try deleteFile("test", dir);
    try std.fs.cwd().deleteDir("tmp");
}
```

***Note: The dir can be null and it will use cwd.***

# Array

All data type have an array equivalent. To write an array, you need to first encode it using `allocEncodArray` before writing it. 
This use an allocator so you need to free what it return.

When read, an array is just the raw bytes. To get the data itself, you need to create an `ArrayIterator`. Here an example:

```zig
pub fn main() !void {
    const allocator = std.testing.allocator;

    // 0. Make a temporary directory
    try std.fs.cwd().makeDir("array_tmp");
    const dir = try std.fs.cwd().openDir("array_tmp", .{});

    // 1. Create a file
    try createFile("test", dir);

    // 2. Create and encode some Data
    const int_array = [4]i32{ 32, 11, 15, 99 };
    const data = [_]Data{
        Data.initIntArray(try allocEncodArray.Int(allocator, &int_array)), // Encode
    };
    defer allocator.free(data[0].IntArray); // DOnt forget to free it

    // 3. Create a DataWriter
    var dwriter = try DataWriter.init("test", dir);
    defer dwriter.deinit();

    // 4. Write some data
    try dwriter.write(&data);
    try dwriter.flush();

    // 5. Create a schema
    const schema = &[_]DType{
        .IntArray,
    };

    // 6. Create a DataIterator
    var iter = try DataIterator.init(allocator, "test", dir, schema);
    defer iter.deinit();

    // 7. Iterate over data
    var i: usize = 0;
    if (try iter.next()) |row| {

        // 8. Iterate over array
        var array_iter = ArrayIterator.init(&row[0]); // Sub array iterator
        while (array_iter.next()) |d| {
            try std.testing.expectEqual(int_array[i], d.Int);
            i += 1;
        }

    }

    try deleteFile("test", dir);
    try std.fs.cwd().deleteDir("array_tmp");
} 
```

# Benchmark

Done on a AMD Ryzen 7 7800X3D with a Samsung SSD 980 PRO 2TB (up to 7,000/5,100MB/s for read/write speed) on one thread.

| Rows | Write Time (ms) | Average Write Time (μs) | Read Time (ms) | Average Read Time (μs) | File Size (kB) |
| --- | --- | --- | --- | --- | --- |
| 1             | 0.01      | 13.63 | 0.025     | 25.0  | 0.04      |
| 10            | 0.01      | 1.69  | 0.03      | 3.28  | 0.4       |
| 100           | 0.04      | 0.49  | 0.07      | 0.67  | 4.0       |
| 1_000         | 0.36      | 0.36  | 0.48      | 0.48  | 40        |
| 10_000        | 3.42      | 0.34  | 4.67      | 0.47  | 400       |
| 100_000       | 36.39     | 0.36  | 48.00     | 0.49  | 4_000     |
| 1_000_000     | 361.41    | 0.36  | 481.00    | 0.48  | 40_000    |

TODO: Update number to use Unix one. Benchmark on my laptop and maybe on some cloud VM.

Data use:
```zig
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
```

***Note: You can check Benchmark.md in ZipponDB to see performance using multi-threading. Was able to parse 1_000_000 users in less than 100ms***

# Importing the package

Create a `build.zig.zon` next to `build.zig` if not already done.

Add this dependencies in `build.zig.zon`:
```zig
.ZipponData = .{
    .url = "git+https://github.com/MrBounty/ZipponData",
    //the correct hash will be suggested by zig},
```

Here what my complete `build.zig.zon` is for my project ZipponDB:
```zig
.{
    .name = "ZipponDB",
    .version = "0.1.4",
    .dependencies = .{
        .ZipponData = .{
            .url = "git+https://github.com/MrBounty/ZipponData",
            //the correct hash will be suggested by zig}, 
    },
    .paths = .{
        "",
    },
}
```

And in `build.zig` you can import the module like this:
```zig
const zid = b.dependency("ZipponData", .{});
exe.root_module.addImport("ZipponData", zid.module("ZipponData"));
```

And you can now import it like std in your project:
```zig
const zid = @import("ZipponData");
zid.createFile("Hello.zid", null);
```

# What you can't do

You can't update files. You gonna need to implement that yourself. The easier way (and only I know), is to parse the entire file and write it into another.

Here an example that evaluate all struct using a `Filter` and write only struct that are false. (A filter can be like `age > 20`, if the member `age` of the struct is `> 20`, it is true):
```zig
pub fn delete(file_name: []const u8, dir: std.fs.Dir, filter: Filter) !void {
    // 1. Create the iterator of the current file
    var iter = try zid.DataIterator.init(self.allocator, file_name, dir, sstruct.zid_schema);
    defer iter.deinit();

    // 2. Create a new file
    const new_path_buff = try std.fmt.allocPrint(self.allocator, "{s}.new", .{file_name});
    defer self.allocator.free(new_path_buff);
    try zid.createFile(new_path_buff, dir);

    // 3. Create a writer of the new data
    var new_writer = try zid.DataWriter.init(new_path_buff, dir);
    defer new_writer.deinit();

    // 4. For all struct, evaluate and write to new file if false
    while (try iter.next()) |row| {
        if (!filter.evaluate(row)) {
            try new_writer.write(row);
        }
    }

    // 5. Flush, delete old file and rename new file to previous file
    try new_writer.flush();
    try dir.deleteFile(path_buff);
    try dir.rename(new_path_buff, path_buff);
}
```

# Potential update

I don't plan do update this but it will depend if my other project need it.

- Functions to update files
- Add a header with the data type at the beginning of the file so no need to make a schema and I can check everytime I write if it's in the good format 
- More type
- Multi threading

