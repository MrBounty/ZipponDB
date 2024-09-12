# ZipponDB

Open-source database written 100% in zig.

![alt text](https://github.com/MrBounty/ZipponDB/blob/main/logo.jpeg)

# Introduction

ZipponDB is a relational database written entirely in Zig from stractch.  
It use a custom query language named ZipponQL or ZiQL for short.

The first time you run ZipponDB, it will create a new ZipponDB directory and start the Zippon CLI.  
From here, you can create a new engine by running `schema build`. It will get the file `schema.zipponschema` and build a custom binary
using zig that the CLI will then use to manipulate data. You then interact with the engine by using `run "My query go here"` or
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

Note: [] are list of value.

# ZipponQL

Zippon have it's own query language. Here the keys point to remember:

- {} Are filters
- [] Are how much; what data
- () Are new or updated data (Not already in file)
- || Are additional options
- Link need to be specify between [] to be return, other are returned automatically
- Data are in struct format and can have link

### Some examples

`GRAB User`  
Get all users

`GRAB User { name = 'Adrien' }`  
Get all user named Adrien

`GRAB User [1; email]`  
Get one user email

`GRAB User | ASCENDING name |`  
Get all users ordered by name

`GRAB User [name] { age > 10 AND name != 'Adrien' } | DECENDING age |`  
Get just the name of all users that are more than 10 years old and not named Adrien

`GRAB User [1] { bestfriend = { name = 'Adrien' } }`  
Get one user that have a best friend named Adrien

`GRAB User [10; friends [1]] { age > 10 } | ASC name |`  
Get one friend of the 10 first user above 10 years old in ascending name.

### Not yet implemented

`GRAB Message [100; comments [ date ] ] { .writter = { name = 'Adrien' }.bestfriend }`  
Get the date of 100 comments written by the best friend of a user named Adrien

`GRAB User { IN Message { date > '12-01-2014' }.writter }`  
Get all users that sended a message after the 12 january 2014

`GRAB User { !IN Comment { }.writter }`  
Get all user that didn't wrote a comment

`GRAB User { IN User { name = 'Adrien' }.friends }`  
Get all user that are friends with an Adrien

`UPDATE User [1] { name = 'Adrien' } => ( email = 'new@email.com' )`  

`REMOVE User { id = '000-000' }`  

`ADD User ( name = 'Adrien', email = 'email', age = 40 )`  

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

[X] CLI  
[ ] Beta without link  
[ ] Relationships/links  
[ ] Multi threading  
[ ] Transaction  
[ ] Docker image  
[ ] Migration of schema  
[ ] Dump/Bump data  
[ ] In memory option  
[ ] Archives  
[ ] Date value type  
