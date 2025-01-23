pub const BUFFER_SIZE = 1024 * 10; // Used a bit everywhere. The size for the schema for example. 10kB
pub const MAX_FILE_SIZE = 1024 * 1024 * 5; // Tried multiple MAX_FILE_SIZE and found 5Mb is good
pub const CPU_CORE = 0; // If 0, take maximum using std.Thread.getCpuCount()

// Debug
pub const PRINT_STATE = false;
pub const DONT_SEND = false;
pub const DONT_SEND_ERROR = false;
pub const RESET_LOG_AT_RESTART = false; // If true, will reset the log file at the start of the db, otherwise just keep adding to it

// Help message
pub const HELP_MESSAGE = struct {
    pub const main: []const u8 =
        \\Welcome to ZipponDB v0.2!
        \\
        \\Available commands:
        \\run       To run a query.
        \\db        Create or chose a database.
        \\schema    Initialize the database schema.
        \\dump      To export data in other format and backup.
        \\quit      Stop the CLI with memory safety.
        \\
        \\For more informations: https://mrbounty.github.io/ZipponDB/cli
        \\
    ;
    pub const db: []const u8 =
        \\Available commands:
        \\use       Select or create a folder to use as database.
        \\metrics   Print some metrics of the current database.
        \\state     Print the current db state (Ok, MissingSchemaEngine, MissingFileEngine).
        \\
        \\For more informations: https://mrbounty.github.io/ZipponDB/cli
        \\    
    ;
    pub const schema: []const u8 =
        \\Available commands:
        \\describe  Print the schema use by the currently database.
        \\use       Take the path to a schema file and initialize the database.
        \\
        \\For more informations: https://mrbounty.github.io/ZipponDB/cli
        \\
    ;
    pub const dump: []const u8 =
        \\Available commands:
        \\csv       Export all database in a csv format.
        \\json      Export all database in a json format. (Not implemented)
        \\zid       Export all database in a zid format. (Not implemented)
        \\
        \\For more informations: https://mrbounty.github.io/ZipponDB/cli
        \\
    ;
    pub const no_engine: []const u8 =
        \\To start using ZipponDB you need to create a new database.
        \\This is a directory/folder that will be use to store data, logs, backup, ect.
        \\To create one use 'db new path/to/directory'. E.g. 'db new data'.
        \\Or use an existing one with 'db use'.
        \\
        \\You can also set the environment variable ZIPPONDB_PATH to the desire path.
        \\
        \\For more informations: https://mrbounty.github.io/ZipponDB/cli
        \\
    ;
    pub const no_schema: []const u8 =
        \\A database was found here `{s}` but no schema find inside. 
        \\To start a database, you need to attach it a schema using a schema file.
        \\By using 'schema use path/to/schema'. For more informations on how to create a schema: TODO add link
        \\
        \\You can also set the environment variable ZIPPONDB_SCHEMA to the path to a schema file.
        \\
        \\For more informations: https://mrbounty.github.io/ZipponDB/Schema
        \\
    ;
};
