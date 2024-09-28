# How the file system work

# All class of ZipponDB

## Tokenizer

All tokenizer are inspiered (highly ;) ) by the Zig tokenizer. https://github.com/ziglang/zig/blob/master/lib/std/zig/tokenizer.zig

Each tokenizer have it's own token. Each token have multiple tag in the form of an enum. For example the CLI Token can have all those tag:

```zig
pub const Tag = enum {
  eof,
  invalid,

  keyword_run,
  keyword_help,
  keyword_describe,
  keyword_schema,
  keyword_build,
  keyword_quit,

  string_literal,
  identifier,
};
```

The tokenizer take a buffer as an array of character (u8) when init, it is the text to tokenize.  
Then a unique function next, that will iterate over each characther of the buffer and find the next token. The token can be invalid and is then return.

### ZiQL

The ZiQL tokenizer is the main tokenizer. It is the one that tokenize query.

### CLI

The CLI tokenizer is the one that take command and do stuff. It is the simplier as it only have keywords like run, help and describe. As well as string for query (Betwwen "").

### Schema

The schema tokenizer take the .zipponschema file and generate the dtypes.zig file that is then use to build the engine.

## DataEngine

The DataEngine is the class that do stuff with files. Nowhere else should file be manipulate.

## Parser

All Parser take a tokenizer and an allocator and do stuff.

### ZiQL

The ZiQL Parser will take the tokenizer and do stuff depending of the main action (GRAB, DELETE, ADD, UPDATE).

### CLI

The CLI doesnt really have a Parser struct but the main function of the console act like it. Maybe I will do a proper Parser in the future.

### Schema

TODO
