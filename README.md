![alt text](https://github.com/MrBounty/ZipponDB/blob/main/docs/images/banner.png)

ZipponDB is a database written entirely in Zig from scratch with 0 dependencies.

ZipponDB's goal is to be ACID, light, simple, and high-performance. It aims at small to medium applications that don't need fancy features but a simple and reliable database.

Key Features:

* **Small:** Binary is small, around 2-3Mb.
* **Fast:** Parse millions of entities in milliseconds.
* **Relationship:** Build with focus on easy relationship.
* **Query Language:** Use it's own simple query language.
* **No dependencies:** Depend on nothing, every line of code running is in the codebase.
* **Open-source:** Open-source under MIT licence.
* **Portable:** Easily compiled and deployed across various platforms.

For more informations visit the docs: https://mrbounty.github.io/ZipponDB/

***Note: ZipponDB is still in Alpha v0.2, see roadmap.***

# Declare a schema

In ZipponDB, you use structures, or structs for short, and not tables to organize how your data is stored and manipulated. A struct has a name like `User` and members like `name` and `age`.

Create a file that contains a schema that describes all structs. Compared to SQL, you can see it as a file where you declare all table names, column names, data types, and relationships. 
All structs have an id of the type UUID by default.

Here an example of a file:
```lua
User (
    name: str,
    age: int,
    email: str,
    Parent: User,
    childrens: []User,
    orders: []Order,
)

Order (
    at: datetime,
    items: []Item,
)

Item (
    name: str,
    category: str,
)
```

Note that parent is a link to another `User` and can be `none`, `[]` mean an array. You can find more examples [here](https://github.com/MrBounty/ZipponDB/tree/main/schema).

# ZipponQL

ZipponDB uses its own query language, ZipponQL or ZiQL for short. Here are the key points to remember:
- 4 actions available: `GRAB`, `ADD`, `UPDATE`, `DELETE`
- All queries start with an action followed by a struct name
- `{}` are filters
- `[]` specify how much and what data
- `()` contain new or updated data (not already in the file)

## GRAB

The main action is `GRAB`, it parse files and return data.  
```js
GRAB User {name = 'Bob' AND (age > 30 OR age < 10)}
```

Using `[]` before the filter tell what to return.  
```js
GRAB User [id, email] {name = 'Bob'}
```

Relationship use filter within filter.
```js
GRAB User {best_friend IN {name = 'Bob'}}
```

GRAB queries return a list of JSON objects, e.g:
```
[{id:"1e170a80-84c9-429a-be25-ab4657894653", name: "Gwendolyn Ray", age: 70, email: "austin92@example.org", scores: [ 77 ], friends: [], }, ]
```

## ADD

The `ADD` action adds one entity to the database. The syntax is similar to `GRAB`, but uses `()`. This signifies that the data is not yet in the database.
```js
ADD User (name = 'Bob', age = 30)
```

## DELETE

Similar to `GRAB` but deletes all entities found using the filter and returns a list of deleted UUIDs.
```js
DELETE User {name = 'Bob'}
```

## UPDATE

A mix of `GRAB` and `ADD`. It takes a filter first, then the new data.
Here, we update the first 5 `User` entities named 'bob' to capitalize the name and become 'Bob':
```js
UPDATE User [5] {name='bob'} TO (name = 'Bob')
```

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
