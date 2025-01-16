# Vs SQL

A good way to see how ZipponQl work is to compare it to SQL.

## Select everything

```
SELECT * FROM User
```

```
GRAB User {}
```

---

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

---

## Select something

```
SELECT name, age
FROM Users
LIMIT 100
```

```go
GRAB User [100; name, age] {}
```

---

## Relationship


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

---

SQL:
```
SELECT Users.name, Orders.orderID, Orders.orderDate
FROM Users
INNER JOIN Orders ON Users.UserID = Orders.UserID;
```

ZiQL:
```go
GRAB User [name, order [id, date]] {}
```

---

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

ZiQL:
```go
GRAB User
[ name, orders [id, date, details [quantity, products [name, category [name]]]]]
{ orders IN {date >= 2023/01/01 AND details.products.category.name != 'Accessories' } } // (1)!
| orders.date DESC | // (2)!
```

1.  Dot not yet implemented. But you can do it with:
    ```
    details IN { products IN {category IN {name != 'Accessories'}}}
    ```
2.  Ordering not yet implemented

---

SQL:
```
UPDATE orders o
JOIN customers c ON o.customer_id = c.customer_id
SET o.status = 'Priority'
WHERE c.membership_level = 'Premium' AND o.order_date > '2023-01-01';
```

ZiQL:
```go
GRAB User.orders { membership_level = 'Premium' } // (1)!
=> premium_order => // (2)!
UPDATE Order {id IN premium_order AND date > 2023/01/01}
TO (status = 'Priority')
```

1.  Not yet implemented. Can't do it now.  
    Here that mean filter are done on User but it return Order.  
    It return all order of User with a premium membership.

2.  Linked query not implemented

