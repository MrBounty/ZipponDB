# ADD

The `ADD` action adds entities to the database. The syntax is similar to `GRAB`, but uses `()`. This signifies that the data is not yet in the database.

Here's an example:
```lua
ADD User (name = 'Bob', age = 30, email = 'bob@email.com', scores = [1 100 44 82])
```

You need to specify all members when adding an entity (default values comming).


The `ADD` query will return a list of added IDs, e.g.:
```
["1e170a80-84c9-429a-be25-ab4657894653", "1e170a80-84c9-429a-be25-ab4657894654", ]
```

And you can also add them in batch 
```
ADD User (name = 'Bob', age = 30, email = 'bob@email.com', scores = [1 100 44 82]) (name = 'Bob2', age = 33, email = 'bob2@email.com', scores = [])
```

You don't need to specify member's name for the second entity as long as the order is respected:
```
ADD User 
(name = 'Bob', age = 30, email = 'bob@email.com', scores = [1 100 44 82])
('Bob2', 33, 'bob2@email.com', [])
```

* Default value
* Array default is empty
* Link default is none

