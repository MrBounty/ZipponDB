# DELETE

Similar to `GRAB` but deletes all entities found using the filter and returns a list of deleted UUIDs.
```js
DELETE User {name = 'Bob'}
```

The `DELETE` query will return a list of deleted IDs, e.g.:
```
["1e170a80-84c9-429a-be25-ab4657894653", "1e170a80-84c9-429a-be25-ab4657894654", ]
```
