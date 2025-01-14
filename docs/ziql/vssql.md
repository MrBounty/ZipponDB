# Vs SQL

A good way to see how ZipponQl work is to compare it to SQL.

## Select everything

```
SELECT * FROM User
```

```
GRAB User
or
GRAB User {}
```

## Selection on condition

```
SELECT *
FROM Users
WHERE name = 'Bob'
AND (age > 30 OR age < 10);
```

```go
GRAB User {name = 'Bob' AND (age > 30 OR age < 10)}
```

## Select something

```
SELECT name, age
FROM Users
LIMIT 100
```

```go
GRAB User [100; name, age] {}
```

## Relationship

### List of other entity

```
SELECT u1.name AS user_name, GROUP_CONCAT(u2.name || ' (' || u2.age || ')') AS friends_list
FROM Users u1
LEFT JOIN User u2 ON ',' || u1.friends || ',' LIKE '%,' || u2.id || ',%'
WHERE u1.age > 30
GROUP BY u1.name;
```

```go
GRAB User [name, friends [name, age]] {age > 30}
```

### Join

#### Simple one

SQL:
```
SELECT Users.name, Orders.orderID, Orders.orderDate
FROM Users
INNER JOIN Orders ON Users.UsersID = Orders.CustomerID;
```

ZiQL:
```go
GRAB User [name, order [id, date]] {}
```

#### More complexe one

SQL:
```
SELECT 
    U.name AS UserName,
    O.orderID,
    O.orderDate,
    P.productName,
    C.categoryName,
    OD.quantity,
FROM 
    Users U
INNER JOIN Orders O ON U.UserID = O.UserID
INNER JOIN OrderDetails OD ON O.OrderID = OD.OrderID
INNER JOIN Products P ON OD.ProductID = P.ProductID
INNER JOIN Categories C ON P.CategoryID = C.CategoryID
WHERE 
    O.orderDate >= '2023-01-01'
    AND C.categoryName != 'Accessories'
ORDER BY 
    O.orderDate DESC;
```

ZiQL
```go
GRAB User
[ name, orders [id, date, details [quantity]], product [name], category [name] ]
{ orders IN {date >= 2023/01/01} AND category IN {name != 'Accessories'} }
| orders.date DESC | // (1)!
```

1.  Ordering not yet implemented
