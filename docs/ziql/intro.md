# ZipponQL

ZipponDB uses its own query language, ZipponQL or ZiQL for short. 
The language goal is to be minimal, small and simple.
Yet allowing powerful relationship.

Here are the key points to remember:

* 4 actions available: `GRAB`, `ADD`, `UPDATE`, `DELETE`
* All queries start with an action followed by a struct name
* `{}` are filters
* `[]` specify how much and what data
* `()` contain new or updated data (not already in files)
* `||` for ordering
* By default, all members that are not links are returned

***Disclaimer: The language may change a bit over time.***

## Making errors

When you make an error writing ZiQL, you should see something like this to help you understand where you made a mistake:
```lua
Error: Expected string
GRAB User {name = Bob}
                  ^^^ 
```

```
Error: Expected ( or member name.
GRAB User {name = 'Bob' AND {age > 10}}
                            ^    
```

## To return

What is between `[]` are what data to return. You can see it as the column name after `SELECT` in SQL.

Here I return just the name of all users:
```
GRAB User [name] {}
```


Here the 100 first users:
```
GRAB User [100] {}
```

Here the name of the 100 first users:
```
GRAB User [100; name]
```

### For relationship

You can also specify what data to return for each relationship returned. By default, query do not return any relationship.

This will return the name and best friend of all users:
```
GRAB User [name, best_friend] {}
```

You can also specify what the best friend return:

```
GRAB User [name, best_friend [name, age]] {}
```

## Filters

What is between `{}` are filters, basically as a list of condition. This filter is use when parsing files and evaluate entities. You can see it as `WHERE` in SQL.

For example `{ name = 'Bob' }` will return `true` if the member `name` of the evaluated entity is equal to `Bob`. This is the most important thing in ZipponDB.

Here an example in a query:

```
GRAB User {name = 'Bob' AND age > 44}
```

### For relationship

Filter can be use inside filter. This allow simple yet powerfull relationship.

This query will return all users that have a best friend named 'Bob'.

```
GRAB User {best_friend IN {name = 'Bob'}}
```

You are obviously not limited to one depth. This will return all users that ordered at least one book in 2024:

```go
GRAB User {
  orders IN {
    products IN {
      category IN {
        name = 'Book'
      }
    },
    date > 2024/01/01
  }
}
```

Same as:
```go
GRAB User {orders IN { products.category.name = 'Book' AND date > 2024/01/01} } // (1)!
```

1.  Dot not yet implemented


## Link query - Not yet implemented

You can also link query. Each query returns a list of UUID of a specific struct. You can use it in the next query.
Here an example where I create a new `Comment` that I then append to the list of comment of one specific `User`.
```
ADD Comment (content='Hello world', at=NOW, like_by=[], by={id='000'}) 
=> added_comment =>
UPDATE User {id = '000'} TO (comments APPEND added_comment)
```

The name between `=>` is the variable name of the list of UUID used for the next queries, you can have multiple one if the link has more than 2 queries.
You can also just use one `=>` but the list of UUID is discarded in that case.

This can be use with GRAB too. So you can create variable before making the query. Here an example:
```
GRAB User {name = 'Bob'} => bobs =>
GRAB User {age > 18} => adults =>
GRAB User {IN adults AND !IN bobs}
```

Which is the same as:
```
GRAB User {name != 'Bob' AND age > 18}
```

Another example:
```
GRAB Product [1] {category.name = 'Book'} => book =>
GRAB Order {date > 2024/01/01 AND products IN book} => book_orders =>
GRAB User [100] {orders IN book_orders}
```
