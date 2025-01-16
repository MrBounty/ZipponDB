# Quickstart

This guide will help you set up and start using ZipponDB quickly.

## Step 1: Get a Binary

Obtain a binary for your architecture by:

- Downloading a pre-built binary from the [releases page](https://github.com/MrBounty/ZipponDB/releases)
- Building from [source code](https://mrbounty.github.io/ZipponDB/build)

Once with the binary, run it to get access to the CLI.

## Step 2: Select a Database

Once in the CLI, create a database by running:
```bash
db use path/to/dir
```

Alternatively, set the `ZIPPONDB_PATH` environment variable.

## Step 3: Attach a Schema

Define a [schema](/ZipponDB/Schema) and attach it to the database by running:

```bash
schema use path/to/schema.txt
```

This will create the necessary directories and empty files for data storage. Test the current database schema by running:

```bash
schema describe
```

Alternatively, set the `ZIPPONDB_SCHEMA` environment variable.

## Step 4: Use the Database

Start using the database by sending queries, such as:

```bash
run "ADD User (name = 'Bob')"
```

[Learn more about ZiQL.](/ZipponDB/ziql/intro)
