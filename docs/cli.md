# Command Line Interface

ZipponDB use a CLI to interact, there is few commands available for now as focus was given to ZiQL. But more commands will be added in the future.

## run

Run a ZiQL query on the selected database.

**Usage:**

```
run QUERY
```

## db

### db metrics

Print some metrics from the db, including: Size on disk and number of entities stored.

**Usage:**

```
db metrics [OPTIONS]
```

**Options:**

Name | Type | Description         | Default
---- | ---- | ------------------- | ----
TODO | TODO | TODO | TODO

### db new

Create a new empty directory that can be then initialize with a schema.

**Usage:**

```
db new path/to/dir [OPTIONS]
```

**Options:**

Name | Type | Description         | Default
---- | ---- | ------------------- | ----
TODO | TODO | TODO | TODO

### db use

Select an already created database with `db new`.

**Usage:**

```
db use path/to/dir [OPTIONS]
```

**Options:**

Name | Type | Description         | Default
---- | ---- | ------------------- | ----
TODO | TODO | TODO | TODO

### db state - WIP

Return the state of the database, either `MissingDatabase` if no database selected or `MissingSchema` if no schema was initialize.

**Usage:**

```
db state
```

## schema

### schema init

Initialize the database using a schema file.

**Usage:**

```
schema use path/to/schema.file [OPTIONS]
```

**Options:**

Name | Type | Description         | Default
---- | ---- | ------------------- | ----
TODO | TODO | TODO | TODO

### schema describe

Print the schema use by the selected database.

**Usage:**

```
schema use path/to/schema.file [OPTIONS]
```

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
