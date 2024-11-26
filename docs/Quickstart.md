# Quickstart

This guide will help you set up and start using ZipponDB quickly.

## Step 1: Get a Binary

Obtain a binary for your architecture by:

- Building from source code (tutorial coming soon)
- Downloading a pre-built binary from the releases page (coming soon)

## Step 2: Create a Database

Run the binary to start the Command Line Interface. Create a new database by running:

``` bash
db new path/to/directory
```
This will create a new ZipponDB directory. Verify the creation by running:

``` bash
db metrics
```

## Step 3: Select a Database

Select a database by running:
```bash
db use path/to/ZipponDB
```

Alternatively, set the `ZIPPONDB_PATH` environment variable to the path of a valid ZipponDB directory (containing DATA, BACKUP, and LOG directories).

## Step 4: Attach a Schema

Define a schema (see the next section for details) and attach it to the database by running:

```bash
schema init path/to/schema.txt
```

This will create the necessary directories and empty files for data storage. Test the current database schema by running:

```bash
schema describe
```

## Step 5: Use the Database

Start using the database by sending queries, such as:

```bash
run "ADD User (name = 'Bob')"
```

You're now ready to explore the features of ZipponDB!