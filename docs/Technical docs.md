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

TODO: Explain ZipponData and how it works.

## Engines

TODO: Explain

### DBEngine

TODO: Explain

### FileEngine

The file engine is responsible for managing files, including reading and writing. This section is not detailed, as it is expected to change in the future.

### SchemaEngine

TODO: Explain

### ThreadEngine

TODO: Explain

## Multi-threading

ZipponDB uses multi-threading to improve performance. Each struct is saved in multiple `.zid` files, and a thread pool is used to process files concurrently. Each thread has its own buffered writer, and the results are concatenated and sent once all threads finish.

The only shared atomic values between threads are the number of found structs and the number of finished threads. This approach keeps things simple and easy to implement, avoiding parallel threads accessing the same file.

## Filters

TODO: Explain the data strucutre and how it works.

## AdditionalData

TODO: Explain the data strucutre and how it works.

## Condition

TODO: Explain the data strucutre and how it works.

## NewData

TODO: Explain the data strucutre and how it works.