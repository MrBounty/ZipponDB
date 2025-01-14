# Interface

Interfaces are way to use ZipponDB from other programming language.

## Python

**Not yet implemented, to give a general idea. Exact code may change.**

```python
from zippondb import Client

db = Client("data")
db.run("ADD User (name='Bob')")
```

### Pydantic

I will most likely implement with Pydantic. Something like that:

```python
from zippondb import Client, Model

class User(Model):
  name: str
  age: int

db = Client("data")
users = db.run("GRAB User {}", model=User)
```

`Model` is like `BaseModel` from pydantic but all member are optional. If no model provided, return a list of dict.

## Golang

TODO
