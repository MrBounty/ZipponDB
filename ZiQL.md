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

# Making erros

When you do an error writting ZiQL, you should see something like this to help you understand where you did a mistake:
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

# Examples

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

Use multiple condition:
```js
GRAB User {name = 'Bob' AND (age > 30 OR age < 10)}
```

GRAB query return a list of JSON with the data inside, e.g:
```
[{id:"1e170a80-84c9-429a-be25-ab4657894653", name: "Gwendolyn Ray", age: 70, email: "austin92@example.org", scores: [ 77 ], friends: [], }, ]
```

#### Not yet implemented

To order it using the name:
```js
GRAB User [10; name] {age > 10} |ASC name|
```

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

ADD query return a list ids added, e.g:
```
["1e170a80-84c9-429a-be25-ab4657894653", "1e170a80-84c9-429a-be25-ab4657894654", ]
```

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

#### Not yet implemented

DELETE query return a list ids deleted, e.g:
```
["1e170a80-84c9-429a-be25-ab4657894653", "1e170a80-84c9-429a-be25-ab4657894654", ]
```

## UPDATE

A mix of `GRAB` and `ADD`. This take a filter first, then the new data.  
Here we update the 5 first User named `adrien` to add a capital and become `Adrien`.
```js
UPDATE User [5] {name='adrien'} TO (name = 'Adrien')
```

Note that compared to `ADD`, you don't need to specify all member between `()`. Only the one specify will be updated.

#### Not yet implemented

UPDATE query return a list ids updated, e.g:
```
["1e170a80-84c9-429a-be25-ab4657894653", "1e170a80-84c9-429a-be25-ab4657894654", ]
```

You can use operations on itself too when updating:
```js
UPDATE User {name = 'Bob'} TO (age += 1)
```

You can also manipulate array, like adding or removing values.
```js
UPDATE User {name='Bob'} TO (scores APPEND 45)
UPDATE User {name='Bob'} TO (scores APPEND [45 99])
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
