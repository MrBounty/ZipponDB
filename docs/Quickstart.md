TODO: Update this part

# Quickstart

1. **Get a binary:** You can build the binary directly from the source code for any architecture (tutorial is coming), or using the binary in the release (coming too).
2. **Create a database:** You can then run the binary, this will start a Command Line Interface. The first thing to do is to create a new database. For that, run the command `db new path/to/directory`,
it will create a ZipponDB directory. Then `db metrics` to see if it worked.
3. **Select a database:** You can select a database by using `db use path/to/ZipponDB`. You can also set the environment variable ZIPPONDB_PATH, and it will use this path,
this needs to be the path to a directory with proper DATA, BACKUP, and LOG directories.
4. **Attach a schema:** Once the database is created, you need to attach a schema to it (see next section for how to define a schema). For that, you can run `schema init path/to/schema.txt`.
This will create new directories and empty files used to store data. You can test the current db schema by running `schema describe`.
5. **Use the database:** ou can now start using the database by sending queries like that: `run "ADD User (name = 'Bob')"`.
