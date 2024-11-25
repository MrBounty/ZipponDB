# Schema

In ZipponDB, you use structures, or structs for short, and not tables to organize how your data is stored and manipulated. A struct has a name like `User` and members like `name` and `age`.

## Create a Schema

ZipponDB use a seperate file to declare all structs to use in the database.

Here an example of a file:
```
User (
    name: str,
    email: str,
    best_friend: User,
)
```

Note that `best_friend` is a link to another `User`.

Here is a more advanced example with multiple structs:
```
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

***Note: `[]` before the type means an array of this type.***

## Migration to a new schema - Not yet implemented

In the future, you will be able to update the schema, such as adding a new member to a struct, and update the database. For the moment, you can't change the schema once it's initialized.

## Commands

`schema init path/to/schema.file`: Init the database using a schema file.

`schema describe`: Print the schema use by the currently selected database.
