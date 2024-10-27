pub const BUFFER_SIZE = 1024 * 50; // Line limit when parsing file
pub const MAX_FILE_SIZE = 5e+6; // 5Mb
pub const CSV_DELIMITER = ';'; // TODO: Delete

// Testing
pub const TEST_DATA_DIR = "test_data/v0.1.2"; // Maybe put that directly in the build

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
};
