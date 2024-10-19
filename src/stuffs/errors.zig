pub const ZiQlParserError = error{
    SynthaxError,
    MemberNotFound,
    MemberMissing,
    StructNotFound,
    FeatureMissing,
    ParsingValueError,
    ConditionError,
    WriteError,
};

pub const SchemaParserError = error{
    SynthaxError,
    FeatureMissing,
    ValueParsingError,
    MemoryError,
};

pub const FileEngineError = error{
    SchemaFileNotFound,
    SchemaNotConform,
    DATAFolderNotFound,
    StructFolderNotFound,
    CantMakeDir,
    CantMakeFile,
    CantOpenDir,
    CantOpenFile,
    MemoryError,
    StreamError,
    ReadError, // TODO: Only use stream
    InvalidUUID,
    InvalidDate,
    InvalidFileIndex,
    DirIterError,
    WriteError,
    FileStatError,
    DeleteFileError,
    RenameFileError,
    StructNotFound,
    MemberNotFound,
};

pub const ZipponError = ZiQlParserError || FileEngineError || SchemaParserError;
