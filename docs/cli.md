# Command Line Interface

ZipponDB use a CLI to interact, there is few commands available for now as focus was given to ZiQL. But more commands will be added in the future.

## run

Run a ZiQL query on the selected database.

**Usage:**

```go
run "QUERY" // (1)!
```

1. Note that query need to be between ""

## db

### db metrics

Print some metrics from the db, including: Size on disk and number of entities stored.

**Usage:**

```
db metrics
```

### db new

Create a new empty directory that can be then initialize with a schema.

**Usage:**

```
db new path/to/dir
```

### db use

Select an already created database with `db new`.

**Usage:**

```
db use path/to/dir
```

### db state

Return the state of the database, either `Ok` or `MissingDatabase` if no database selected or `MissingSchema` if no schema was initialize.

**Usage:**

```
db state
```

## schema

### schema use

Attach a schema to the database using a schema file.

**Usage:**

```
schema use path/to/schema.file 
```

### schema describe

Print the schema use by the selected database.

**Usage:**

```
schema describe
```

## dump

Export the entier database in a specific format.

**Usage:**

```
dump [FORMAT] [PATH]
```

FORMAT options: `csv`, `json`, `zid`

## quit

Quit the CLI.

**Usage:**

```
quit
```

## help

Write an help message.

**Usage:**

```
help
```
