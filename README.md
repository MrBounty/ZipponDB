![alt text](https://github.com/MrBounty/ZipponDB/blob/main/banner.png)

# Introduction

ZipponDB is a relational database written entirely in Zig from stractch.  
It use a custom query language named ZipponQL or ZiQL for short.

The first time you run ZipponDB, it will create a new ZipponDB directory and start the Zippon CLI.  
From here, you can create a new engine by running `schema build`. It will use the file `schema.zipponschema` and build a custom binary
using zig, that the CLI will then use to manipulate data. You then interact with the engine by using `run "My query go here"` or
by directly using the engine binary.

### Why Zippon ?

- Open-source and written 100% in Zig with 0 dependency
- Relational database
- Small, fast and implementable everywhere

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

In this example each user have a name and email as a string. But also one best friend as a link. 

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

Zippon have it's own query language. Here the keys point to remember:

- {} Are filters
- [] Are how much; what data
- () Are new or updated data (Not already in file); Or to link condition between {}
- || Are additional options
- By default all member that are not link are return
- To return link or just some member, specify them between []

## Examples
| Command | Description |
| --- | --- |
| GRAB User | Get all users |
| GRAB User { name = 'Adrien' } | Get all users named Adrien |
| GRAB User [1; email] | Get one user's email |
| GRAB User \| ASCENDING name \| | Get all users ordered by name |
| GRAB User [name] { age > 10 AND name != 'Adrien' } \| DECENDING age \| | Get just the name of all users that are more than 10 years old and not named Adrien |
| GRAB User [1] { bestfriend = { name = 'Adrien' } } | Get one user that has a best friend named Adrien |
| GRAB User [10; friends [1]] { age > 10 } | Get one friend of the 10th user above 10 years old |

### Not yet implemented
| Command | Description |
| --- | --- |
| GRAB Message [100; comments [ date ] ] { .writter = { name = 'Adrien' }.bestfriend } | Get the date of 100 comments written by the best friend of a user named Adrien |
| GRAB User { IN Message { date > '12-01-2014' }.writter } | Get all users that sent a message after the 12th January 2014 |
| GRAB User { !IN Comment { }.writter } | Get all users that didn't write a comment |
| GRAB User { IN User { name = 'Adrien' }.friends } | Get all users that are friends with an Adrien |
| UPDATE User [1] { name = 'Adrien' } => ( email = 'new@email.com' ) | Update a user's email |
| REMOVE User { id = '000-000' } | Remove a user by ID |
| ADD User ( name = 'Adrien', email = 'email', age = 40 ) | Add a new user |

# Integration

For now there is only a python intregration, but because it is just 2-3 command, it is easy to implement with other language.

### Python

```python
import zippondb as zdb

client = zdb.newClient('path/to/binary')
client.exe('schema build')
print(client.exe('schema describe'))

# Return named tuple of all users
users = client.run('GRAB User {}')
for user in users:
    print(user.name)
```

# Roadmap

v 0.1 - Base  
[X] UUID  
[X] CLI  
[X] Tokenizers  
[ ] File management
[ ] Base Parser  

v 0.2 - Usable  
[ ] B-Tree
[ ] Relationships  
[ ] Date  
[ ] Docker  

v 0.3 - QoL  
[ ] Schema migration   
[ ] Dump/Bump data  
[ ] Recovery

v 0.4 - Usability  
[ ] Server  
[ ] Python interface  
[ ] Go interface  

v 0.5 - In memory  
[ ] In memory option  
[ ] Cache

v 0.6 - Performance  
[ ] Transaction  
[ ] Lock manager
[ ] Multi threading 

v 0.7 - Safety  
[ ] Auth
[ ] Metrics

v 0.6 - Advanced  
[ ] Query optimizer

v 1.0 - Web interface
[ ] Query builder
[ ] Tables
[ ] Schema visualization
[ ] Dashboard metrics
