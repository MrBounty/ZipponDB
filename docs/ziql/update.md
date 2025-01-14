# UPDATE

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

## Not yet implemented

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
UPDATE User {name='Bob'} TO (comments REMOVE [1] { at < '2023/12/31'})
```

I may include more options later.
