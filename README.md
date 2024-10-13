![alt text](https://github.com/MrBounty/ZipponDB/blob/main/logo/banner.png)

# Introduction

ZipponDB is a relational database written entirely in Zig from scratch with 0 dependency.  

ZipponDB goal is to be ACID, light, simple and high performance. It aim small to medium application that don't need fancy features but a simple and reliable database.

### Why Zippon ?

- Relational database (Soon)
- Simple and minimal query language
- Small, light, fast and implementable everywhere

# Quickstart

1. **Get a binary:** You can build the binary directly from the source code for any architecture (tuto is comming), or using the binary in the release (comming too).
2. **Create a database:** You can then run the binary, this will start a Command Line Interface. The first thing to do is to create a new database. For that run the command `db new path/to/directory`, 
it will create a `ZipponDB` directory. Then `database metrics` to see if it worked.
3. **Select a database:** You can select a database by using `db use path/to/ZipponDB`. You can also set the environment variable ZIPPONDB_PATH and it will and use this path, 
this need to be the path to a directory with proper DATA, BACKUP and LOG directory.
4. **Attach a schema:** Once the database created, you need to attach a schema to it (see next section for how to define a schema). For that you can run `schema init path/to/schema.txt`. 
This will create new directories and empty files used to store data.  You can test the current db schema by running `schema describe`.
5. **Use the database:** You can now start using the database by sending query like that: `run "ADD User (name = 'Bob')"`.

***Note: For the moment ZipponDB use the current working directory as main directory so all path are a sub_path of it.***

# Declare a schema

In ZipponDB you use structures, or struct for short, and not tables to organize how your data is store and manipulate. A struct have a name like `User` and members like `name` and `age`.

Create a file with inside a schema that describe all structs. Compared to SQL, you can see it as a file where you declare all table name, columns name, data type and relationship. All struct have an id of the type UUID by default.

Here an example of a file:
```lua
User (
    name: str,
    email: str,
    best_friend: User,
)
```

Note that the best friend is a link to another `User`.

Here a more advance example with multiple struct:
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

Note: `[]` before the type mean a list/array of this type.

### Migration to a new schema - Not yet implemented

In the future, you will be able to update the schema like add a new member to a struct and update the database. For the moment, you can't change the schema once init.

# ZipponQL

ZipponDB use it's own query language, ZipponQL or ZiQL for short. Here the keys point to remember:

- 4 actions available: `GRAB` `ADD` `UPDATE` `DELETE`
- All query start with an action then a struct name
- `{}` For filters
- `[]` For how much; what data
- `()` For new or updated data (Not already in file)
- `||` For additional options

***Disclaimer: Lot of stuff are still missing and the language may change over time.***

## Quickstart

**For more information see [ZiQL Introduction](https://github.com/MrBounty/ZipponDB/blob/main/ZiQL.md)**

### GRAB

The main action is `GRAB`, this will parse files and return data.
```js
GRAB User {name = 'Bob' AND (age > 30 OR age < 10)}
```

GRAB query return a list of JSON with the data inside, e.g:
```
[{id:"1e170a80-84c9-429a-be25-ab4657894653", name: "Gwendolyn Ray", age: 70, email: "austin92@example.org", scores: [ 77 ], friends: [], }, ]
```

### ADD

The `ADD` action will add one entity into the database.
```js
ADD User (name = 'Bob', age = 30, email = 'bob@email.com', scores = [1 100 44 82])
```

### DELETE

Similare to `GRAB` but delete all entity found using the filter.
```js
DELETE User {name = 'Bob'}
```

### UPDATE

A mix of `GRAB` and `ADD`. This take a filter first, then the new data.  
Here we update the 5 first User named `bob` to add a capital and become `Bob`.
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

You can also link query. Each query return a list of UUID of a specific struct. You can use it in the next query.
Here an example where I create a new `Comment` that I then append to the list of comment of one specific `User`.
```js
ADD Comment (content='Hello world', at=NOW, like_by=[]) => added_comment => UPDATE User {id = '000'} TO (comments APPEND added_comment)
```

The name between `=>` is the variable name of the list of UUID used for the next queries, you can have multiple one if the link have more than 2 queries. You can also just use one `=>` but the list of UUID is discard in that case.

# Data types

Their is 5 data type for the moment:
- `int`: 64 bit integer
- `float`: 64 bit float. Need to have a dot, `1.` is a float `1` is an integer.
- `bool`: Boolean, can be `true` or `false`
- `string`: Character array between `''`
- `UUID`: Id in the UUID format, used for relationship, ect. All struct have an id member.

Comming soon:
- `date`: A date in yyyy/mm/dd
- `datetime`: A date time in yyyy/mm/dd/hh/mm/ss
- `time`: A time in hh/mm/ss

All data type can be an array of those type using [] in front of it. So []int is an array of integer.

All data type can also be `null`. Expect array that can only be empty.

# Why I created it ?

Well the first reason is to learn, both zig and databases.

The second is to use it in my apps. I like to deploy Golang + HTMX app on Fly.io but I often find myself struggelling to get a simple database.
I can either host it myself but I need to link my app and the db securely. Or use a cloud db service but that mean my db is far from my app.
All I want is to give to a Fly machine 10go of storage, do some backup on it and call it a day. But for that I need to include it to the Dockerfile of my app, what easier way than just a binary ?

So that my goal long term, to use it in my apps as a simple database that live WITH the app, sharing CPU and memory.

# How does it work ?

TODO: Create a tech doc of what is happening inside.

# Roadmap

***Note: This will probably evolve over time.***

#### v0.1 - Base  
- [X] UUID  
- [X] CLI  
- [X] Tokenizers  
- [X] ZiQL parser
- [X] Schema engine  
- [X] File engine  

#### v0.2 - Usable  
- [ ] B+Tree  
- [ ] Relationships  
- [ ] Date
- [ ] Linked query
- [ ] Docker  

#### v0.3 - QoL  
- [ ] Schema migration   
- [ ] Dump/Bump data  
- [ ] Recovery
- [ ] Better CLI
- [ ] Logs

#### v0.4 - Usability  
- [ ] Server  
- [ ] Config file
- [ ] Python interface  
- [ ] Go interface  

#### v0.5 - In memory  
- [ ] In memory option  
- [ ] Cache

#### v0.6 - Performance  
- [ ] Transaction  
- [ ] Multi threading
- [ ] Lock manager 
- [ ] Optimized data file

#### v0.7 - Safety  
- [ ] Auth  
- [ ] Metrics
- [ ] Durability

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

Let's see where it (or my brain) start explode ;)
