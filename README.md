# ZipponDB

Note: Make a stupide mascotte

# Written in Zig

Zig is fast, blablabla

# How it's work

Meme "That's the neat part..."

Zippon is a strutural relational potentially in memory written entirely in Zig from stractch.

You build a binary according to your schema, you can just run it with some arguments and it will create and manage a folder 'zipponDB_DATA'.
Then you do what you want with it, including:
- Run it with your app as a file and folder
- Create a Docker and open some port
- Create a Docker with a small API
- Other stuffs, Im sure some will find something nice

Note that you can have multiple binary that run together. Each binary have a unique id that is use to segregate binary inside the folder 'zipponDB_DATA'

# Benchmark

# Create a schema

Zippon use struct as way of saving data. A struct is a way of storing multiple data of different type.
Very similar to a row in a table, columns being datatype and a row a single struct.

The schema is directly INSIDE the binary, so each binary are per schema ! This is for effenciency, idk to be honest, I guess ? lol

# Migration

For now you can't migrate the data of one binary to another, so you will need to different binary.

# Zippon language

Ok so I went crazy on that, on have it how language. It is stupide and I love it. I wanted to do like EdgeDB but no, too simple.
Anyway, I tried to do something different, to do something different, idk, you're the jduge of it.

```
GRAB User { name = 'Adrien' }
Get all user named Adrien

GRAB User [1; email] { }
Get one email

GRAB User {} | ASCENDING name |
Get all users ordered by name

GRAB User [name] { age > 10 AND name != 'Adrien' } | DECENDING age |
Get just the name of all users that are 10 years old or more and not named Adrien ordered by age

GRAB User { bestfriend = { name = 'Adrien' } }
GRAB User { bestfriend = User{ name = 'Adrien' } } // Same
Get all user that have a best friend named Adrien

GRAB User [10] { IN User [1] { age > 10 } | ASC name |.friends }
Get 10 users that are friend with the first user older than 10 years old in ascending name order

GRAB Message [100; comments [ date ] ] { .writter = { name = 'Adrien' }.bestfriend }
Get the date of 100 comments from the best friend of the writter named Adrien

GRAB User { IN Message { date > '12-01-2014' }.writter }
Get all users that sended a message after the 12 january 2014

GRAB User { !IN Comment { }.writter }
Get all user that didn't wrote a comment

GRAB User { IN User { name = 'Adrien' }.friends }
Get all user that are friends with an Adrien

UPDATE User [1] { name = 'Adrien' } => ( email = 'new@email.com' )

REMOVE User { id = '000-000' }

ADD User ( name = 'Adrien', email = 'email', age = 40 }
```

- {} Are filters
- [] Are how much; what data
- () Are new or updated data (Not already savec)
- || Are additional options
- Data are in struct format and can have link


# How it's really work

NOTE: Do this in a separe file

## Tokenizer

The tokenizer of the language is 
# ZipponDB
