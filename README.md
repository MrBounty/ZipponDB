![alt text](https://github.com/MrBounty/ZipponDB/blob/main/logo/banner.png)

# Introduction

ZipponDB is a relational database written entirely in Zig from stractch with 0 dependency.  

ZipponDB goal is to be ACID, light, simple and high performance. It is aim for small to medium application that don't need fancy features but a simple and reliable database.  

### Why Zippon ?

- Open-source and written 100% in Zig with 0 dependency
- Relational database
- Simple and minimal query language
- Small, light, fast and implementable everywhere

# Declare a schema

ZipponDB need a schema to work. A schema is a way to define how your data will be store. 

Compared to SQL, you can see it as a file where you declare all table name, columns name, data type and relationship. 

But here you declare struct. A struct have a name and members. A member is one data or link and have a type associated. Here a simple example for a user:

```
User (
    name: str,
    email: str,
    best_friend: User,
)
```

Note that the best friend is a link to another User.

Here a more advance example with multiple struct:
```
User {
    name: str,
    email: str,
    friends: []User,
    posts: []Post,
    liked_posts: []Post,
    comments: []Comment,
    liked_coms: []Comment,
}

Post {
    title: str,
    image: str,
    at: date,
    from: User,
    like_by: []User,
    comments: []Comment,
}

Comment {
    content: str,
    at: date,
    from: User,
    like_by: []User,
    of: Post,
}
```

Can be simplify to take less space but can require more complexe query:

```
User {
    name: str,
    email: str,
    friends: []User,
    posts: []Post,
    comments: []Comment,
}

Post {
    title: str,
    image: str,
    at: date,
    like_by: []User,
    comments: []Comment,
}

Comment {
    content: str,
    at: date,
    like_by: []User,
}
```

Note: [] are list of value.

# ZipponQL

ZipponDB use it's own query language, ZipponQL or ZiQL for short. Here the keys point to remember:

- 4 actions available: `GRAB` `ADD` `UPDATE` `DELETE`
- All query start with an action then a struct name
- {} Are filters
- [] Are how much; what data
- () Are new or updated data (Not already in file)
- || Are additional options
- By default all member that are not link are return
- To return link or just some member, specify them between []

## GRAB

The main action is `GRAB`, this will parse files and return data. Here how it's work:

```
GRAB StructName [number_of_entity_max; member_name1, member_name2] { member_name1 = value1}
```

Note that `[]` and `{}` are both optional.  
So this will work and return all User without any filtering:
```
GRAB User
```

Here a simple example where to get all User above 18 years old:
```
GRAB User {age > 18}
```

To just return the name of User:
```
GRAB User [name] {age > 18}
```

To return the 10 first User:
```
GRAB User [10] {age > 18}
```

You can use both:
```
GRAB User [10; name] {age > 18}
```

To order it using the name:
```
GRAB User [10; name] {age > 10} |ASC name|
```

## ADD

The `ADD` action will add one entity into the database (batch are comming).  
The synthax is similare but use `()`, this mean that the data is not yet in the database if between `()`.

Here an example:
```
ADD User (name = 'Bob', age = 30, email = 'bob@email.com', scores = [1 100 44 82])
```

You need to specify all member when adding an entity (default value are comming).

## DELETE

Similare to `GRAB` but delete all entity found using the filter and return the list of UUID deleted.
```
DELETE User {name = 'Bob'}
```

## UPDATE

A mix of `GRAB` and `ADD`. This take a filter first, then the new data.  
Here we update the 5 first User named `adrien` to add a capital and become `Adrien`.
```
UPDATE User [5] {name='adrien'} => (name = 'Adrien')
```

Note that compared to `ADD`, you don't need to specify all member between `()`. Only the one specify will be updated.

## Examples list
| Command | Description |
| --- | --- |
| GRAB User | Get all users |
| GRAB User { name = 'Adrien' } | Get all users named Adrien |
| GRAB User [1; email] | Get one user's email |
| GRAB User \| ASC name \| | Get all users ordered by name |
| GRAB User [name] { age > 10 AND name != 'Adrien' } | Get users' name if more than 10 years old and not named Adrien |
| GRAB User { age > 10 AND (name = 'Adrien' OR  name = 'Bob'} | Use multiple condition |
| UPDATE User [1] { name = 'Adrien' } => ( email = 'new@email.com' ) | Update a user's email |
| REMOVE User { id = '000-000' } | Remove a user by ID |
| ADD User ( name = 'Adrien', email = 'email', age = 40 ) | Add a new user |

### Not yet implemented
| Command | Description |
| --- | --- |
| GRAB User { age > 10 AND name IN ['Adrien' 'Bob']} | In comparison |
| GRAB User [1] { bestfriend IN { name = 'Adrien' } } | Get one user that has a best friend named Adrien |
| GRAB User [10; friends [1]] { age > 10 } | Get one friend of the 10th user above 10 years old |
| GRAB Message [100; comments [ date ] ] { writter IN { name = 'Adrien' }.bestfriend } | Get the date of 100 comments written by the best friend of a user named Adrien |
| GRAB User { IN Message { date > '12-01-2014' }.writter } | Get all users that sent a message after the 12th January 2014 |
| GRAB User { !IN Comment { }.writter } | Get all users that didn't write a comment |
| GRAB User { IN User { name = 'Adrien' }.friends } | Get all users that are friends with an Adrien |

# Data types

Their is 5 data type for the moment:
- `int`: 64 bit integer
- `float`: 64 bit float
- `bool`: Boolean, can be `true` or `false`
- `string`: Character array between `''`
- `uuid`: Id in the UUID format, used for relationship, ect. All struct have an id member.

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

# Roadmap

#### v0.1 - Base  
- [X] UUID  
- [X] CLI  
- [X] Tokenizers  
- [ ] ZiQL parser
- [ ] Schema engine  
- [X] File engine  
- [ ] Loging 

#### v0.2 - Usable  
- [ ] B-Tree  
- [ ] Relationships  
- [ ] Date  
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
