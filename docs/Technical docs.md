# Intro

TODO

***Note: Code snippets in this documentation are simplified examples and may not represent the actual codebase.***

## Tokenizers

Tokenizers are responsible for converting a buffer string into a list of tokens. Each token has a `Tag` enum that represents its type, such as `equal` for the `=` symbol, and a `Loc` struct with start and end indices that represent its position in the buffer.

All tokenizers work similarly and are based on the [zig tokenizer.](https://github.com/ziglang/zig/blob/master/lib/std/zig/tokenizer.zig) They have two main methods: next, which returns the next token, and getTokenSlice, which returns the slice of the buffer that represents the token.

Here's an example of how to use a tokenizer:
```zig
const toker = Tokenizer.init(buff);
const token = toker.next();
std.debug.print("{s}", .{toker.getTokenSlice(token)});
```

Tokenizers are often used in a loop until the `end` tag is reached. In each iteration, the next token is retrieved and processed based on its tag. Here's a simple example:
```zig
const toker = Tokenizer.init(buff);
var token = toker.next();
while (token.tag != .end) : (token = toker.next()) switch (token.tag) {
  .equal => std.debug.print("{s}", .{toker.getTokenSlice(token)}),
  else => {},
}
```

### Available Tokenizers

There are four different tokenizers in ZipponDB:

- **ZiQL:** Tokenizer for the query language.
- **cli:** Tokenizer the commands.
- **schema:** Tokenizer for the schema file.

Each tokenizer has its own set of tags and parsing rules, but they all work similarly.

## Parser

Parsers are the next step after tokenization. They take tokens and perform actions or raise errors. There are three parsers in ZipponDB: one for ZiQL, one for schema files, and one for CLI commands.

A parser has a `State` enum and a `Tokenizer` instance as members, and a parse method that processes tokens until the `end` state is reached.

Here's an example of how a parser works:
```zig
var state = .start;
var token = self.toker.next();
while (state != .end) : (token = self.toker.next()) switch (state) {
  .start => switch (token.tag) {
    .identifier => self.addStruct(token),
    else => printError("Error: Expected a struct name.", token),
  },
  else => {},
}
```

The parser's state is updated based on the combination of the current state and token tag. This process continues until the `end` state is reached.

The ZiQL parser uses different methods for parsing:

- `parse`: The main parsing method that calls other methods.
- `parseFilter`: Creates a filter tree from the query.
- `parseCondition`: Creates a condition from a part of the query.
- `parseAdditionalData`: Populates additional data from the query.
- `parseNewData`: Returns a string map with key-value pairs from the query.
- `parseOption`: Not implemented yet.

## File parsing

File parsing is done through a small library that I did named [ZipponData](https://github.com/MrBounty/ZipponData). 

It is minimal and fast, it can parse 1_000_000 entity in 0.3s on one thread 
on a 7 7800X3D at around 4.5GHz with a Samsung SSD 980 PRO 2TB (up to 7,000/5,100MB/s for read/write speed).

To read a file, you create an iterator for a single file and then you can iterate with `.next()`. It will return an array of `Data`. This make everything very easy to use.

```zig
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

## Engines

ZipponDB segregate responsability with Engines.

For example the `FileEngine` is the only place where files used, for both writting and reading. This simplify refactoring, testing, etc.

### DBEngine

This is just a wrapper around all other Engines to keep them at the same place. This doesnt do anything except storing other Engines.

This can be find in `main.zig`, in the `main` function.

### FileEngine

The `FileEngine` is responsible for managing files, including reading and writing.

Most methods will parse all files of a struct and evaluate them with a filter and do stuff if `true`. For example `parseEntities` will parse all entities and if the filter return `true`, 
will write using the writer argument a JSON object with the entity's data.

Those methods are usually sperated into 2 methods. The main one and a `OneFile` version, e.g. `parseEntitiesOneFile`. The main one will call a thread for each file using multiple `OneFile` version.
This is how multi-threading is done.

### SchemaEngine

The `SchemaEngine` manage everything related to schemas. 

This is mostly used to store a list of `SchemaStruct`, with is just one struct as defined in the schema. With all member names, data types, links, etc.

This is also here that I store the `UUIDFileIndex`, that is a map of UUID to file index. So I can quickly check if a UUID exist and in which file it is store.
This work well but use a bit too much memory for me, around 220MB for 1_000_000 entities. I tried doing a Radix Trie but it doesn't use that much less memory, maybe I did a mistake somewhere.

### ThreadEngine

The `ThreadEngine` manage the thread pool of the database.

This is also where is stored the `ThreadSyncContext` that is use for each `OneFile` version of parsing methods in the `FileEngine`. This is the only atomix value currently used in the database.

## Multi-threading

ZipponDB uses multi-threading to improve performance. Each struct is saved in multiple `.zid` files, and a thread pool is used to process files concurrently. Each thread has its own buffered writer, and the results are concatenated and sent once all threads finish.

The only shared atomic values between threads are the number of found structs and the number of finished threads. This approach keeps things simple and easy to implement, avoiding parallel threads accessing the same file.

## Data Structures

### AdditionalData

TODO: Explain the data strucutre and how it works.

### Filters

A filter is a series of condition. It use a tree approach, by that I mean the filter have a root node that is either a condition or have 2 others nodes (left and right).

For example the filter `{name = 'Bob'}` have one root node that is the condition. So when I evaluate the struct, I just check this condition.

Now for like `{name = 'Bob' AND age > 0}`, the root node have as left node the condition `name = 'Bob'` and right node the condition `age > 0`.

To look like that:
```
            AND
         /      \
        OR      OR
       / \      / \
    name name age age
    ='A' ='B' >80 <20
```

### Condition

A condition is part of filters. It is one 'unit of condition'. For example `name = 'Bob'` is one condition.
`name = 'Bob' and age > 0` are 2 conditions and one filter. It is created inside `parseCondition` in the `ziqlParser`.

A condition have those infos:

- value: ConditionValue. E.g. `32`
- operation: ComparisonOperator. E.g. `equal` or `in`
- data_type: DataType. E.g. `int` or `str`
- data_index: usize. This is the index in when parsing returned by zid `DataIterator`

### NewData

NewData is a map with member name as key and ConditionValue as value, it is created when parsing and is use to add data into a file.
I transform ConditionValue into Zid Data. Maybe I can directly do a map member name -> zid Data ?

### RelationMap

TODO: Explain.

## EntityWriter

This is responsable to transform the raw Data into a JSON, Table or other output format to send send to end user.
Basically the last step before sending.
