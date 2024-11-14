# ZipponQL

ZipponDB uses its own query language, ZipponQL or ZiQL for short. Here are the key points to remember:
- 4 actions available: `GRAB`, `ADD`, `UPDATE`, `DELETE`
- All queries start with an action followed by a struct name
- `{}` are filters
- `[]` specify how much and what data
- `()` contain new or updated data (not already in the file)
- `||` are additional options
- By default, all members that are not links are returned
- To return links or only some members, specify them between []

***Disclaimer: A lot of features are still missing, and the language may change over time.***

# Making errors

When you make an error writing ZiQL, you should see something like this to help you understand where you made a mistake:
```
Error: Expected string
GRAB User {name = Bob}
                  ^^^ 
```

```
Error: Expected ( or member name.
GRAB User {name = 'Bob' AND {age > 10}}
                            ^    
```

# Data types

There is 5 data types for the moment:
- `int`: 64 bit integer
- `float`: 64 bit float. Need to have a dot, `1.` is a float `1` is an integer.
- `bool`: Boolean, can be `true` or `false`
- `string`: Character array between `''`
- `UUID`: Id in the UUID format, used for relationship, ect. All struct have an id member.
- `date`: A date in yyyy/mm/dd
- `time`: A time in hh:mm:ss.mmmm
- `datetime`: A date time in yyyy/mm/dd-hh:mm:ss:mmmm

All data types can be an array of those types using `[]` in front of it. So `[]int` is an array of integer.

All data types can also be `null`. Except arrays that can only be empty.

# Examples

## GRAB

The main action is `GRAB`, this will parse files and return data.  

Here's how to return all `User` entities without any filtering:
```js
GRAB User
```

To get all `User` entities above 18 years old:
```js
GRAB User {age > 18}
```

To return only the `name` member of `User` entities:
```js
GRAB User [name] {age > 18}
```

To return the 10 first `User` entities:
```js
GRAB User [10] {age > 18}
```

You can combine these options:
```js
GRAB User [10; name] {age > 18}
```

Use multiple conditions:
```js
GRAB User {name = 'Bob' AND (age > 30 OR age < 10)}
```

GRAB queries return a list of JSON objects with the data inside, e.g:
```
[{id:"1e170a80-84c9-429a-be25-ab4657894653", name: "Gwendolyn Ray", age: 70, email: "austin92@example.org", scores: [ 77 ], friends: [], }, ]
```

#### Not yet implemented

To order the results by `name`:
```js
GRAB User [10; name] {age > 10} |ASC name|
```

You can specify how much data to return and which members to include, even for links inside structs. In this example, I get 1 friend's name for 10 `User` entities:
```js
GRAB User [10; friends [1; name]]
```

##### Using IN 
You can use the `IN` operator to check if something is in an array:
```js
GRAB User { age > 10 AND name IN ['Adrien' 'Bob']}
```

This also works by using other filters. Here I get `User` entities that have a best friend named Adrien:
```js
GRAB User { bestfriend IN { name = 'Adrien' } }
```

When using an array with `IN`, it will return all User entities that have AT LEAST one friend named Adrien:
```js
GRAB User { friends IN { name = 'Adrien' } }
```

To get `User` entities with all friends named Adrien:
```js
GRAB User { friends ALLIN { name = 'Adrien' } }
```

You can use `IN` on itself. Here I get all `User` entities that liked a `Comment` from 2024. Both queries return the same result:
```js
GRAB User { IN Comment {at > '2024/01/01'}.like_by}
GRAB Comment.like_by { at > '2024/01/01'}
```

You can obtain a similar result with this query, but it will return a list of `Comment` entities with a `liked_by` member that is similar to the `User` entities above. If you take all `liked_by` members inside all `Comment` entities, it will be the same list, but you can end up with duplicates since one `User` can like multiple `Comment` entities.
```js
GRAB Comment [liked_by] {at > '2024/01/01'}
```

##### Return relationship

You can also return a relationship only. The filter will be applied to `User` entities, but will return `Comment` entities:
```js
GRAB User.comments {name = 'Bob'}
```

You can do it as much as you like. This will return all `User` that liked comments from Bob:
```js
GRAB User.comments.like_by {name = 'Bob'}
```

This can also be used inside filters. Note that we need to specify `User` because it is a different struct than `Post`. Here, I get all `Post` entities that have a comment from Bob:
```js
GRAB Post {comments IN User{name = 'Bob'}.comments}
```

You can also do the same but only for the first Bob found:
```js
GRAB Post {comments IN User [1] {name = 'Bob'}.comments}
```

Be careful; this will return all `User` entities that liked a comment from 10 `User` entities named Bob:
```js
GRAB User.comments.like_by [10] {name = 'Bob'}
```

To get 10 `User` entities that liked a comment from any `User` entity named Bob, you need to use:
```js
GRAB User.comments.like_by [comments [like_by [10]]] {name = 'Bob'}
```

##### Using !
You can use `!` to return the opposite. When used with `IN`, it checks if something is NOT in the list. When used with filters, it returns entities that do not match the filter.

This will return all `User` entities that didn't like a `Comment` in 2024:
```js
GRAB User { !IN Comment {at > '2024/01/01'}.like_by}
```

Be careful because this does not return the same thing as above; it returns all `User` entities that liked a `Comment` not in 2024:
```js
GRAB Comment.like_by !{ at > '2024/01/01'}
```

Which is the same as:
```js
GRAB Comment.like_by { at < '2024/01/01'}
```

## ADD

The `ADD` action adds one entity to the database. The syntax is similar to `GRAB`, but uses `()`. This signifies that the data is not yet in the database.

Here's an example:
```js
ADD User (name = 'Bob', age = 30, email = 'bob@email.com', scores = [1 100 44 82])
```

You need to specify all members when adding an entity (default values are coming soon).


The `ADD` query will return a list of added IDs, e.g.:
```
["1e170a80-84c9-429a-be25-ab4657894653", "1e170a80-84c9-429a-be25-ab4657894654", ]
```

#### Not yet implemented

And you can also add them in batch 
```js
ADD User (name = 'Bob', age = 30, email = 'bob@email.com', scores = [1 100 44 82]) (name = 'Bob2', age = 33, email = 'bob2@email.com', scores = [])
```

You don't need to specify the members in the second entity as long as the order is respected:
```js
ADD User (name = 'Bob', age = 30, email = 'bob@email.com', scores = [1 100 44 82]) ('Bob2', 33, 'bob2@email.com', [])
```

## DELETE

Similar to `GRAB` but deletes all entities found using the filter and returns a list of deleted UUIDs.
```js
DELETE User {name = 'Bob'}
```

The `DELETE` query will return a list of deleted IDs, e.g.:
```
["1e170a80-84c9-429a-be25-ab4657894653", "1e170a80-84c9-429a-be25-ab4657894654", ]
```

## UPDATE

A mix of `GRAB` and `ADD`. It takes a filter first, then the new data.
Here, we update the first 5 `User` entities named 'adrien' to capitalize the name and become 'Adrien':
```js
UPDATE User [5] {name='adrien'} TO (name = 'Adrien')
```

Note that, compared to `ADD`, you don't need to specify all members between `()`. Only the ones specified will be updated.

The `UPDATE` query will return a list of updated IDs, e.g.:
```
["1e170a80-84c9-429a-be25-ab4657894653", "1e170a80-84c9-429a-be25-ab4657894654", ]
```

#### Not yet implemented

You can use operations on values themselves when updating:
```js
UPDATE User {name = 'Bob'} TO (age += 1)
```

You can also manipulate arrays, like adding or removing values:
```js
UPDATE User {name='Bob'} TO (scores APPEND 45)
UPDATE User {name='Bob'} TO (scores APPEND [45 99])
UPDATE User {name='Bob'} TO (scores REMOVEAT [0 1 2])
```

Currently, there will be four keywords for manipulating lists:
- `APPEND`: Adds a value to the end of the list.
- `REMOVE`: Checks the list, and if the same value is found, deletes it.
- `REMOVEAT`: Deletes the value at a specific index.
- `CLEAR`: Removes all values from the array.

Except for `CLEAR`, which takes no value, each keyword can use one value or an array of values. If you choose an array, it will perform the operation on all values in the array.

For relationships, you can use filters:
```js
UPDATE User {name='Bob'} TO (comments APPEND {id = '000'})
UPDATE User {name='Bob'} TO (comments REMOVE { at < '2023/12/31'})
```

I may include more options later.

# Date

***WIP***

## Date

To write a date, you use this format: `yyyy/mm/dd`.
Like that: `2024/10/19`.

***Note: You cant use negative years***

## Time

To write a time, you use this format: `hh:mm:ss.mmmmm`.
Like that: `12:45:00.0000`.

Millisecond and second are optional so this work too: `12:45:00` and `12:45`


## Datetime

Mix of both, to write a datetime, you use this format: `yyyy/mm/dd-hh:mm:ss.mmmmm`.
Like that: `2024/10/19-12:45:00.0000`.

Millisecond and second are optional so this work too: `2024/10/19-12:45:00` and `2024/10/19-12:45`

GRAB User {birthday > 2020/10/19 AND birthday < 2024/01/01 }

GRAB IOT {id = '0000-0000' AND .TemperatureSensor.Temperature.timestamp > 22-45-50.0000}
GRAB IOT {.TemperatureSensor.TemperatureRecord IN TemperatureRecord{.timestamp > 22-45-50.0000 AND version = 3}}
GRAB IOT {.TemperatureSensor.TemperatureRecord IN .{timestamp > 22-45-50.0000} AND .TemperatureSensor IN .{version = 3}}
