# Intro

TODO

***Note: Code snipped do not necessary represent the actual codebase but are use to explain principle.***

# Tokenizers

All `Tokenizer` work similary and are based on the [zig tokenizer.](https://github.com/ziglang/zig/blob/master/lib/std/zig/tokenizer.zig)

The `Tokenizer` role is to take a buffer string and convert it into a list of `Token`. A token have an enum `Tag` that represent what the token is, for example `=` is the tag `equal`, and a `Loc` with a `start` and `end` usize that represent the emplacement in the buffer.

The `Tokenizer` itself have 2 methods: `next` that return the next `Token`. And `getTokenSlice` that return the slice of the buffer that represent the `Token`, using it's `Loc`.

This is how to use it:
```zig
const toker = Tokenizer.init(buff);
const token = toker.next();
std.debug.print("{s}", .{toker.getTokenSlice(token)});
```

I usually use a `Tokenizer` in a loop until the `Tag` is `end`. And in each loop I take the next token and will use a switch on the `Tag` to do stuffs.

Here a simple example:
```zig
const toker = Tokenizer.init(buff);
var token = toker.next();
while (token.tag != .end) : (token = toker.next()) switch (token.tag) {
  .equal => std.debug.print("{s}", .{toker.getTokenSlice(token)}),
  else => {},
}
```

### All tokenizers

There is 4 differents tokenizer in ZipponDB, I know, that a lot. Here the list:
- **ZiQL:** Tokenizer for the query language.
- **cli:** Tokenizer the commands.
- **schema:** Tokenizer for the schema file.
- **data:** Tokenizer for csv file.

They all have different `Tag` and way to parse the array of bytes but overall are very similar. The only noticable difference is that some use a null terminated string (based on the zig tokenizer) and other not.
Mostly because I need to use dupeZ to get a new null terminated array, not necessary.

# Parser

`Parser` are the next step after the tokenizer. Its role is to take `Token` and do stuff or raise error. There is 3 `Parser`, the main one is for ZiQL, one for the schema and one for the cli. 
Note that the cli one is just the `main` function in `main.zig` and not it's own struct but overall do the same thing.

A `Parser` have a `State` and a `Tokenizer` as member and have a `parse` method. Similary to `Tokenizer`, it will enter a while loop. This loop will continue until the `State` is `end`.

Let's take as example the schema parser that need to parse this file:
```
User (name: str)
```

When I run the `parse` method, it will init the `State` as `start`. When in `start`, I check if the `Token` is a identifier (a variable name), if it is one I add it to the list of struct in the current schema, if not I raise an error pointing to this token. 
Here the idea for a `parse` method:
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

The issue here is obviously that we are in an infinite loop that just going to add struct or print error. I need to change the `state` based on the combinaison of the current `state` and `token.tag`. For that I usually use very implicite name for `State`.
For example in this situation, after a struct name, I expect `(` so I will call it something like `expect_l_paren`. Here the idea:
```zig
var state = .start;
var token = self.toker.next();
while (state != .end) : (token = self.toker.next()) switch (state) {
  .start => switch (token.tag) {
    .identifier => {
        self.addStruct(token);
        state = .expect_l_parent;
      },
    else => printError("Error: Expected a struct name.", token),
  },
  .expect_l_parent => switch (token.tag) {
    .l_paren => {},
    else => printError("Error: Expected (.", token),
  },
  else => {},
}
```

And that's basicly it, the entire `Parser` work like that. It is fairly easy to debug as I can print the `state` and `token.tag` at each iteration and follow the path of the `Parser`.

Note that the `ZiQLParser` use different methods for parsing:
- **parse:** The main one that will then use the other.
- **parseFilter:** This will create a `Filter`, this is a tree that contain all condition in the query, what is between `{}`.
- **parseCondition:** Create a `Condition` based on a part of what is between `{}`. E.g. `name = 'Bob'`.
- **parseAdditionalData:** Populate the `AdditionalData` that represent what is between `[]`.
- **parseNewData:** Return a string map with key as member name and value as value of what is between `()`. E.g. `(name = 'Bob')` will return a map with one key `name` with the value `Bob`.
- **parseOption:** Not done yet. Parse what is between `||`

# FileEngine

The `FileEngine` is that is managing files, everything that need to read or write into files is here.

I am not goind into too much detail here as I think this will change in the future.

# Multi-threading

How do I do multi-threading ? Basically all struct are saved in multiples `.zid` files. Each files have
a size limit defined in the config and a new one is created when no previous one is found with space left.

When I run a GRAB query and parse all files and evaluate each struct, I use a thread pool and give a file
to each thread. Each thread have it's own buffered writer and once all finished, I concatenate all writer
and send it.

The only atomic value share by all threads are the number of founded struct (to stop thread if enough are found when
[10] is use). And the number of finished thread, so I know when I can concatenate and send stuffs.

Like that this keep things simple and easy to implement. I dont have parallel thread that run different 
that need to access the same file.
