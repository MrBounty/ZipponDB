![alt text](https://github.com/MrBounty/ZipponDB/blob/main/logo/banner.png)

# Introduction

ZipponDB is a relational database written entirely in Zig from stractch with 0 dependency.  

ZipponDB goal is to be ACID, light, simple and high performance. It aim small to medium application that don't need fancy features but a simple and reliable database.  

### Why Zippon ?

- Open-source and written 100% in Zig with 0 dependency
- Relational database
- Simple and minimal query language
- Small, light, fast and implementable everywhere

# Quickstart

You can build the binary directly from the source code (tuto is comming), or using the binary in the release (comming too).

You can then run it, starting a Command Line Interface. The first thing to do is to create a new database. For that run the command `db new path/to/folder`, it will create a `ZipponDB` folder with multiple stuffs inside. Then `database metrics` to see if it worked. You can change between database by using `db swap path/to/ZipponDB`.

Once the database created, you need to attach a schema to it (see next section for how to define a schema). For that you can run `schema init path/to/schema.txt`. This will create new folder and empty files used to store data. 

You can now start using the database by sending query like that: `run "ADD User (name = 'Bob')"`.

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

### Migration to a new schema

***Not yet implemented***

In the future, you will be able to update the schema like add a new member to a struct and update the database. For the moment, you can't change the schema once init.

# ZipponQL

ZipponDB use it's own query language, ZipponQL or ZiQL for short. Here the keys point to remember:

- 4 actions available: `GRAB` `ADD` `UPDATE` `DELETE`
- All query start with an action then a struct name
- `{}` Are filters
- `[]` Are how much; what data
- `()` Are new or updated data (Not already in file)
- `||` Are additional options
- By default all member that are not link are return
- To return link or only some members, specify them between `[]`

***Disclaimer: Lot of stuff are still missing and the language may change over time.***

## GRAB

The main action is `GRAB`, this will parse files and return data.  

Here how to return all `User` without any filtering:
```js
GRAB User
```

To get all `User` above 18 years old:
```js
GRAB User {age > 18}
```

To only return the name of `User`:
```js
GRAB User [name] {age > 18}
```

To return the 10 first `User`:
```js
GRAB User [10] {age > 18}
```

You can use both:
```js
GRAB User [10; name] {age > 18}
```

To order it using the name:
```js
GRAB User [10; name] {age > 10} |ASC name|
```

Use multiple condition:
```js
GRAB User {name = 'Bob' AND (age > 30 OR age < 10)}
```

#### Not yet implemented

You can specify how much and what to return even for link inside struct. In this example I get 1 friend name for 10 `User`:
```js
GRAB User [10; friends [1; name]]
```

##### Using IN 
You can use the `IN` operator to check if something is in an array:
```js
GRAB User { age > 10 AND name IN ['Adrien' 'Bob']}
```

This also work by using other filter. Here I get `User` that have a best friend named Adrien:
```js
GRAB User { bestfriend IN { name = 'Adrien' } }
```

When using an array with IN, it will return all `User` that have at least ONE friend named Adrien:
```js
GRAB User { friends IN { name = 'Adrien' } }
```

To get `User` with ALL friends named Adrien:
```js
GRAB User { friends ALLIN { name = 'Adrien' } }
```

You can use `IN` on itself. Here I get all `User` that liked a `Comment` that is from 2024. Both queries return the same thing:
```js
GRAB User { IN Comment {at > '2024/01/01'}.like_by}
GRAB Comment.like_by { at > '2024/01/01'}
```

You can optain a similar result with this query but it will return a list of `Comment` with a member `liked_by` that is similar to `User` above. If you take all `liked_by` inside all `Comment`, it will be the same list but you can end up with duplicate as one `User` can like multiple `Comment`.
```js
GRAB Comment [liked_by] {at > '2024/01/01'}
```

##### Return relationship

You can also return a relationship only. The filter will be done on `User` but will return `Comment`:
```js
GRAB User.comments {name = 'Bob'}
```

You can do it as much as you like. This will return all `User` that liked comments from Bob:
```js
GRAB User.comments.like_by {name = 'Bob'}
```

This can also be use inside filter. Note that we need to specify `User` because it is a different struct that `Post`. Here I get all `Post` that have a comment from Bob:
```js
GRAB Post {comments IN User{name = 'Bob'}.comments}
```

Can also do the same but only for the first Bob found:
```js
GRAB Post {comments IN User [1] {name = 'Bob'}.comments}
```

Be carefull, this will return all `User` that liked a comment from 10 `User` named Bob:
```js
GRAB User.comments.like_by [10] {name = 'Bob'}
```

To get 10 `User` that liked a comment from any `User` named Bob, you need to use:
```js
GRAB User.comments.like_by [comments [like_by [10]]] {name = 'Bob'}
```

##### Using !
You can use `!` to return the opposite. Use with `IN`, it check if it is NOT is the list. Use it with filters, it return entities that do not respect the filter.

This will return all `User` that didn't like a `Comment` in 2024:
```js
GRAB User { !IN Comment {at > '2024/01/01'}.like_by}
```

Be carefull because this do not return the same, it return all `User` that liked a `Comment` not in 2024:
```js
GRAB Comment.like_by !{ at > '2024/01/01'}
```

Which is the same as:
```js
GRAB Comment.like_by { at < '2024/01/01'}
```

## ADD

The `ADD` action will add one entity into the database.  
The synthax is similare but use `()`, this mean that the data is not yet in the database.

Here an example:
```js
ADD User (name = 'Bob', age = 30, email = 'bob@email.com', scores = [1 100 44 82])
```

You need to specify all member when adding an entity (default value are comming).

#### Not yet implemented

And you can also add them in batch 
```js
ADD User (name = 'Bob', age = 30, email = 'bob@email.com', scores = [1 100 44 82]) (name = 'Bob2', age = 33, email = 'bob2@email.com', scores = [])
```

You don't need to specify the member in the second entity as long as the order is respected.
```js
ADD User (name = 'Bob', age = 30, email = 'bob@email.com', scores = [1 100 44 82]) ('Bob2', 33, 'bob2@email.com', [])
```

## DELETE

Similare to `GRAB` but delete all entity found using the filter and return the list of UUID deleted.
```js
DELETE User {name = 'Bob'}
```

## UPDATE

A mix of `GRAB` and `ADD`. This take a filter first, then the new data.  
Here we update the 5 first User named `adrien` to add a capital and become `Adrien`.
```js
UPDATE User [5] {name='adrien'} TO (name = 'Adrien')
```

Note that compared to `ADD`, you don't need to specify all member between `()`. Only the one specify will be updated.

#### Not yet implemented

You can use operations on itself too when updating:
```js
UPDATE User {name = 'Bob'} TO (age += 1)
```

You can also manipulate array, like adding or removing values.
```js
UPDATE User {name='Bob'} TO (scores APPEND 45)
UPDATE User {name='Bob'} TO (scores REMOVEAT [0 1 2])
```

For now there is 4 keywords to manipulate list:
- `APPEND`: Add value at the end of the list.
- `REMOVE`: Check the list and if the same value is found, delete it.
- `REMOVEAT`: Delete the value at a specific index.
- `CLEAR`: Remove all value in the array.

Except `CLEAR` that take no value, each can use one value or an array of value, if chose an array it will perform the operation on all value in the array.

For relationship, you can use filter on it:
```js
UPDATE User {name='Bob'} TO (comments APPEND {id = '000'})
UPDATE User {name='Bob'} TO (comments REMOVE { at < '2023/12/31'})
```

I may include more options later.

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

# Lexique

- **Struct:** A struct of how to store data. E.g. `User`
- **Entity:** An entity is one instance of a struct.
- **Member:** A member is one data saved in a struct. E.g. `name` in `User`

# How does it work ?

TODO: Create a tech doc of what is happening inside.

# Roadmap

#### v0.1 - Base  
- [X] UUID  
- [X] CLI  
- [X] Tokenizers  
- [ ] ZiQL parser
- [ ] Schema engine  
- [X] File engine  

#### v0.2 - Usable  
- [ ] B-Tree  
- [ ] Relationships  
- [ ] Date
- [ ] Link query
- [ ] Docker  

#### v0.3 - QoL  
- [ ] Schema migration   
- [ ] Dump/Bump data  
- [ ] Recovery
- [ ] Better CLI

#### v0.4 - Usability  
- [ ] Server  
- [ ] Python interface  
- [ ] Go interface  

#### v0.5 - In memory  
- [ ] In memory option  
- [ ] Cache

#### v0.6 - Performance  
- [ ] Transaction  
- [ ] Multi threading
- [ ] Lock manager 

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
