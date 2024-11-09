![alt text](https://github.com/MrBounty/ZipponDB/blob/main/logo/banner.png)

# Introduction

ZipponDB is a relational database written entirely in Zig from scratch with 0 dependencies.

ZipponDB's goal is to be ACID, light, simple, and high-performance. It aims at small to medium applications that don't need fancy features but a simple and reliable database.

### Why Zippon ?

- Relational database (Soon)
- Simple and minimal query language
- Small, light, fast, and implementable everywhere

***Note: ZipponDB is still in Alpha v0.1 and is missing a lot of features, see roadmap at the end of this README.***

# Quickstart

1. **Get a binary:** You can build the binary directly from the source code for any architecture (tutorial is coming), or using the binary in the release (coming too).
2. **Create a database:** You can then run the binary, this will start a Command Line Interface. The first thing to do is to create a new database. For that, run the command `db new path/to/directory`,
it will create a ZipponDB directory. Then `db metrics` to see if it worked.
3. **Select a database:** You can select a database by using `db use path/to/ZipponDB`. You can also set the environment variable ZIPPONDB_PATH, and it will use this path,
this needs to be the path to a directory with proper DATA, BACKUP, and LOG directories.
4. **Attach a schema:** Once the database is created, you need to attach a schema to it (see next section for how to define a schema). For that, you can run `schema init path/to/schema.txt`.
This will create new directories and empty files used to store data. You can test the current db schema by running `schema describe`.
5. **Use the database:** ou can now start using the database by sending queries like that: `run "ADD User (name = 'Bob')"`.

***Note: For the moment, ZipponDB uses the current working directory as the main directory, so all paths are sub-paths of it.***

# Declare a schema

In ZipponDB, you use structures, or structs for short, and not tables to organize how your data is stored and manipulated. A struct has a name like `User` and members like `name` and `age`.

Create a file that contains a schema that describes all structs. Compared to SQL, you can see it as a file where you declare all table names, column names, data types, and relationships. All structs have an id of the type UUID by default.

Here an example of a file:
```lua
User (
    name: str,
    email: str,
    best_friend: User,
)
```

Note that the best friend is a link to another `User`.

Here is a more advanced example with multiple structs:
```lua
User (
    name: str,
    email: str,
    friends: []User,
    posts: []Post,
    comments: []Comment,
)

Post (
    title: str,
    image: str,
    at: date,
    like_by: []User,
    comments: []Comment,
)

Comment (
    content: str,
    at: date,
    like_by: []User,
)
```

***Note: `[]` before the type means a list/array of this type.***

***Note: Members order matter for now!***

### Migration to a new schema - Not yet implemented

In the future, you will be able to update the schema, such as adding a new member to a struct, and update the database. For the moment, you can't change the schema once it's initialized.

# ZipponQL

ZipponDB uses its own query language, ZipponQL or ZiQL for short. Here are the key points to remember:
- 4 actions available: `GRAB`, `ADD`, `UPDATE`, `DELETE`
- All queries start with an action followed by a struct name
- `{}` are filters
- `[]` specify how much and what data
- `()` contain new or updated data (not already in the file)
- `||` are additional options

***Disclaimer: Lot of stuff are still missing and the language may change over time.***

## ZiQL Quickstart

**For more information see [ZiQL Introduction](https://github.com/MrBounty/ZipponDB/blob/main/ZiQL.md)**

### GRAB

The main action is `GRAB`, this will parse files and return data.  
```js
GRAB User {name = 'Bob' AND (age > 30 OR age < 10)}
```

GRAB queries return a list of JSON objects with the data inside, e.g:
```
[{id:"1e170a80-84c9-429a-be25-ab4657894653", name: "Gwendolyn Ray", age: 70, email: "austin92@example.org", scores: [ 77 ], friends: [], }, ]
```

### ADD

The `ADD` action adds one entity to the database. The syntax is similar to `GRAB`, but uses `()`. This signifies that the data is not yet in the database.
```js
ADD User (name = 'Bob', age = 30, email = 'bob@email.com', scores = [1 100 44 82])
```

### DELETE

Similar to `GRAB` but deletes all entities found using the filter and returns a list of deleted UUIDs.
```js
DELETE User {name = 'Bob'}
```

### UPDATE

A mix of `GRAB` and `ADD`. It takes a filter first, then the new data.
Here, we update the first 5 `User` entities named 'bob' to capitalize the name and become 'Bob':
```js
UPDATE User [5] {name='bob'} TO (name = 'Bob')
```

### Not yet implemented

A lot of things are not yet implemented, you can find examples in the [ZiQL Introduction](https://github.com/MrBounty/ZipponDB/blob/main/ZiQL.md).

This include:
- Relationship
- Ordering
- Batch
- Array manipulation
- And more...

## Link query - Not yet implemented

You can also link query. Each query returns a list of UUID of a specific struct. You can use it in the next query.
Here an example where I create a new `Comment` that I then append to the list of comment of one specific `User`.
```js
ADD Comment (content='Hello world', at=NOW, like_by=[]) => added_comment => UPDATE User {id = '000'} TO (comments APPEND added_comment)
```

The name between `=>` is the variable name of the list of UUID used for the next queries, you can have multiple one if the link has more than 2 queries.
You can also just use one `=>` but the list of UUID is discarded in that case.

This can be use with GRAB too. So you can create variable before making the query. Here an example:
```js
GRAB User {name = 'Bob'} => bobs =>
GRAB User {age > 18} => adults =>
GRAB User {IN adults AND !IN bobs}
```

Which is the same as:
```js
GRAB User {name != 'Bob' AND age > 18}
```

# Data types

There is 8 data types:
- `int`: 64 bit integer
- `float`: 64 bit float. Need to have a dot, `1.` is a float `1` is an integer.
- `bool`: Boolean, can be `true` or `false`
- `string`: Character array between `''`
- `UUID`: Id in the UUID format, used for relationship, ect. All struct have an id member.
- `date`: A date in yyyy/mm/dd
- `time`: A time in hh:mm:ss.mmmm
- `datetime`: A date time in yyyy/mm/dd-hh:mm:ss:mmmm

All data types can be an array of those types using `[]` in front of it. So `[]int` is an array of integer.

# Why I created it ?

Well, the first reason is to learn both Zig and databases.

The second is to use it in my apps. I like to deploy Golang + HTMX apps on Fly.io, but I often find myself struggling to get a simple database. I can either host it myself, but then I need to link my app and the database securely. Or I can use a cloud database service, but that means my database is far from my app. All I want is to give a Fly machine 10GB of storage, do some backups on it, and call it a day. But for that, I need to include it in the Dockerfile of my app. What easier way than just a binary?

So that's my long-term goal: to use it in my apps as a simple database that lives with the app, sharing CPU and memory.

# How does it work ?

TODO: Create a tech doc of what is happening inside.

# Roadmap

***Note: This will probably evolve over time.***

### Alpha
#### v0.1 - Base  
- [X] UUID  
- [X] CLI  
- [X] Tokenizers  
- [X] ZiQL parser
- [X] Schema engine  
- [X] File engine  

#### v0.2 - Usable  
- [ ] Relationships  
- [X] Custom data file
- [X] Date
- [ ] Linked query
- [X] Logs
- [X] Query multi threading

#### v0.3 - QoL  
- [ ] Schema migration   
- [ ] Dump/Bump data  
- [ ] Recovery
- [ ] Better CLI

### Beta
#### v0.4 - Usability  
- [ ] Server  
- [ ] Docker  
- [ ] Config file
- [ ] Python interface  
- [ ] Go interface  

#### v0.5 - In memory  
- [ ] In memory option  
- [ ] Cache

#### v0.6 - Performance  
- [ ] Transaction  
- [ ] Other multi threading
- [ ] Query optimization  
- [ ] Index

#### v0.7 - Safety  
- [ ] Auth  
- [ ] Metrics
- [ ] Durability

### Gold
#### v0.8 - Advanced  
- [ ] Query optimizer  

#### v0.9 - Docs  
- [ ] ZiQL tuto  
- [ ] Deployment tuto  
- [ ] Code docs  
- [ ] CLI help

#### v1.0 - Web interface  
- [ ] Query builder  
- [ ] Tables  
- [ ] Schema visualization  
- [ ] Dashboard metrics  

Let's see where it (or my brain) start to explode ;)
