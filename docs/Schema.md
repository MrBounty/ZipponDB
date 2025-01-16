# Schema

In ZipponDB, data is organized and manipulated using structures, or structs, rather than traditional tables. A struct is defined by a name, such as `User`, and members, such as `name` and `age`.

## Defining a Schema

To declare structs for use in your database, create a separate file containing the schema definitions. Below is an example of a simple schema file:
```lua
User (
    name: str,
    email: str,
    best_friend: User,
)
```

In this example, the `best_friend` member is a reference to another `User`.

Here's a more complex example featuring multiple structs:
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

*Note: The [] symbol preceding a type indicates an array of that type. For example, []User represents an array of User structs.*

## Schema Migration - Not yet implemented

In future releases, ZipponDB will support schema updates, allowing you to modify existing structs or add new ones, and then apply these changes to your database. Currently, schema modifications are not possible once the database has been initialized.

I will add commands or query to add, delete and update struct in the schema. Maybe the schema will be a Struct itself with a schema like that:

```lua
Struct (
    name: str,
    members: []Member,
)

Member (
    name: str,
    type: int,
)
```

Like that can just do ZiQL query directly on it.

### Planned Migration Features

- Add new members to existing structs
- Modify or remove existing members
- Rename structs or members
- Update relationships between structs
- More...
