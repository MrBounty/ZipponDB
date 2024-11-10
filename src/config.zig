pub const BUFFER_SIZE = 1024 * 64 * 64; // Line limit when parsing file and other buffers
pub const MAX_FILE_SIZE = 5e+8; // 500Mb
pub const CPU_CORE = 16;

// Testing
pub const TEST_DATA_DIR = "data"; // Maybe put that directly in the build

// Debug
pub const DONT_SEND = true;
pub const RESET_LOG_AT_RESTART = false; // If true, will reset the log file at the start of the db, otherwise just keep adding to it

// Help message
pub const HELP_MESSAGE = struct {
    pub const main: []const u8 =
        \\Welcome to ZipponDB v0.1.1!
        \\
        \\Available commands:
        \\run       To run a query.
        \\db        Create or chose a database.
        \\schema    Initialize the database schema.
        \\quit      Stop the CLI with memory safety.
        \\
        \\For more informations: https://github.com/MrBounty/ZipponDB
        \\
    ;
    pub const db: []const u8 =
        \\Available commands:
        \\new       Create a new database using a path to a sub folder.
        \\use       Select another ZipponDB folder to use as database.
        \\metrics   Print some metrics of the current database.
        \\
        \\For more informations: https://github.com/MrBounty/ZipponDB
        \\    
    ;
    pub const schema: []const u8 =
        \\Available commands:
        \\describe  Print the schema use by the currently selected database.
        \\init      Take the path to a schema file and initialize the database.
        \\
        \\For more informations: https://github.com/MrBounty/ZipponDB
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
        \\For more informations: https://github.com/MrBounty/ZipponDB
        \\
    ;
    pub const no_schema: []const u8 =
        \\A database was found here {s} but no schema find inside. 
        \\To start yousing the database, you need to attach it a schema using a schema file.
        \\By using 'schema init path/to/schema'. For more informations on how to create a schema: TODO add link
        \\
        \\You can also set the environment variable ZIPPONDB_SCHEMA to the path to a schema file.
        \\
        \\For more informations: https://github.com/MrBounty/ZipponDB
        \\
    ;
};
