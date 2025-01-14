# GRAB

The main action is `GRAB`, this will parse files and return data.  

#### Basic

Here's how to return all `User` entities without any filtering:
```
GRAB User
```

---

To get all `User` entities above 30 years old:
```
GRAB User {age > 30}
```

---

To return only the `name` member of `User` entities:
```
GRAB User [name] {age > 30}
```

---

To return the 10 first `User` entities:
```
GRAB User [10] {age > 30}
```

---

You can combine these options:
```
GRAB User [10; name] {age > 30}
```

---

Use multiple conditions:
```
GRAB User {name = 'Bob' AND (age > 30 OR age < 10)}
```

---

GRAB queries return a list of JSON objects with the data inside, e.g:
```
[{id:"1e170a80-84c9-429a-be25-ab4657894653", name: "Gwendolyn Ray", age: 70, email: "austin92@example.org", scores: [ 77 ], friends: [], }, ]
```

---

#### Ordering - Not yet implemented

To order the results by `name`:
```js
GRAB User [10; name] {age > 10} |ASC name|
```

#### Array
You can use the `IN` operator to check if something is in an array:
```js
GRAB User { age > 10 AND name IN ['Adrien' 'Bob']}
```

---

#### Relationship

2 main things to remember with relationship:

* You can use filter inside filter.
* You can use the dot `.` to refer to a relationship. (Not yet implemented)

Get `User` that have a best friend named Adrien:
```js
GRAB User { bestfriend IN { name = 'Adrien' } }
```
---

You can specify how much data to return and which members to include, even for links inside entity. In this example, I get 1 friend's name for 10 `User`:
```js
GRAB User [10; friends [1; name]]
```

---

When using `IN`, it return all `User` that have AT LEAST one friend named Adrien:
```js
GRAB User { friends IN { name = 'Adrien' } }
```
---

To get `User` entities with all friends named Adrien:
```js
GRAB User { friends ALLIN { name = 'Adrien' } }
```
---

You can use `!` to say not in:
```js
GRAB User { friends !IN { name = 'Adrien' } }
```
---

#### Dot - Not yet implemented

You can use `.` if you just want to do one comparison. Here I get all `User` that ordered at least one book:
```js
GRAB User { orders.products.category.name = 'Book' }
```

Same as:
```
GRAB User {orders IN { products IN { category IN { name = 'Book'} } } }
```

