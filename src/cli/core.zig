const std = @import("std");
const config = @import("config");
const Allocator = std.mem.Allocator;

const FileEngine = @import("../file/core.zig");
const SchemaEngine = @import("../schema/core.zig");
const ThreadEngine = @import("../thread/engine.zig");
const ziqlParser = @import("../ziql/parser.zig");
const setLogPath = @import("../main.zig").setLogPath;
const log = std.log.scoped(.cli);

const DBEngineState = enum { MissingFileEngine, MissingSchemaEngine, MissingAllocator, MissingThreadEngine, Ok, Init };

pub const Self = @This();

var path_buffer: [1024]u8 = undefined;
var line_buffer: [config.BUFFER_SIZE]u8 = undefined;
var in_buffer: [config.BUFFER_SIZE]u8 = undefined;
var value_buffer: [1024]u8 = undefined;

usingnamespace @import("parser.zig");

allocator: Allocator = undefined,
state: DBEngineState = .Init,
file_engine: FileEngine = undefined,
schema_engine: SchemaEngine = undefined,
thread_engine: ThreadEngine = undefined,

pub fn init(allocator: Allocator, potential_main_path: ?[]const u8, potential_schema_path: ?[]const u8) Self {
    log.debug("DatabaseEngine Initializing.", .{});
    var self = Self{ .allocator = allocator };

    self.thread_engine = ThreadEngine.init(self.allocator) catch {
        log.err("Error initializing thread engine", .{});
        self.state = .MissingThreadEngine;
        return self;
    };
    log.debug("ThreadEngine initialized.", .{});

    const potential_main_path_or_environment_variable = potential_main_path orelse getEnvVariable(self.allocator, "ZIPPONDB_PATH");
    if (potential_main_path_or_environment_variable) |main_path| {
        setLogPath(main_path);

        log.debug("Found ZIPPONDB_PATH: {s}.", .{main_path});
        self.file_engine = FileEngine.init(self.allocator, main_path, self.thread_engine.thread_pool) catch {
            log.err("Error when init FileEngine", .{});
            self.state = .MissingFileEngine;
            return self;
        };
        self.file_engine.createMainDirectories() catch {
            log.err("Error when creating main directories", .{});
            self.state = .MissingFileEngine;
            return self;
        };

        self.state = .MissingSchemaEngine;
    } else {
        log.debug("No ZIPPONDB_PATH found.", .{});
        self.state = .MissingFileEngine;
        return self;
    }
    log.debug("FileEngine initialized.", .{});

    if (self.file_engine.isSchemaFileInDir() and potential_schema_path == null) {
        const schema_path = std.fmt.bufPrint(&path_buffer, "{s}/schema", .{self.file_engine.path_to_ZipponDB_dir}) catch {
            self.state = .MissingSchemaEngine;
            return self;
        };

        log.debug("Schema founded in the database directory.", .{});
        self.schema_engine = SchemaEngine.init(self.allocator, schema_path, &self.file_engine) catch |err| {
            log.err("Error when init SchemaEngine: {any}", .{err});
            self.state = .MissingSchemaEngine;
            return self;
        };
        self.file_engine.createStructDirectories(self.schema_engine.struct_array) catch |err| {
            log.err("Error when creating struct directories: {any}", .{err});
            self.state = .MissingSchemaEngine;
            return self;
        };

        log.debug("SchemaEngine created in DBEngine with {d} struct", .{self.schema_engine.struct_array.len});

        self.file_engine.schema_engine = self.schema_engine;
        self.state = .Ok;
        log.debug("SchemaEngine initialized.", .{});
        return self;
    }

    if (potential_schema_path == null) log.info("Database don't have any schema yet, trying to add one.", .{});
    const potential_schema_path_or_environment_variable = potential_schema_path orelse getEnvVariable(self.allocator, "ZIPPONDB_SCHEMA");
    if (potential_schema_path_or_environment_variable) |schema_path| {
        log.debug("Found schema path {s}.", .{schema_path});
        self.schema_engine = SchemaEngine.init(self.allocator, schema_path, &self.file_engine) catch |err| {
            log.err("Error when init SchemaEngine: {any}", .{err});
            self.state = .MissingSchemaEngine;
            return self;
        };
        self.file_engine.createStructDirectories(self.schema_engine.struct_array) catch |err| {
            log.err("Error when creating struct directories: {any}", .{err});
            self.state = .MissingSchemaEngine;
            return self;
        };
        self.file_engine.schema_engine = self.schema_engine;
        self.file_engine.writeSchemaFile(self.schema_engine.null_terminated) catch |err| {
            log.err("Error saving schema file: {any}", .{err});
            self.state = .MissingSchemaEngine;
            return self;
        };

        self.state = .Ok;
        log.debug("SchemaEngine initialized.", .{});
    } else {
        log.debug(config.HELP_MESSAGE.no_schema, .{self.file_engine.path_to_ZipponDB_dir});
    }

    return self;
}

pub fn start(self: *Self) !void {
    while (true) {
        std.debug.print("> ", .{}); // TODO: Find something better than just std.debug.print
        const line = std.io.getStdIn().reader().readUntilDelimiterOrEof(&in_buffer, '\n') catch {
            log.debug("Command too long for buffer", .{});
            continue;
        };

        if (line) |line_str| {
            log.debug("Query received: {s}", .{line_str});

            const null_term_line_str = try std.fmt.bufPrintZ(&line_buffer, "{s}", .{line_str});
            if (try self.parse(null_term_line_str)) break;
        }
    }
}

pub fn getEnvVariable(allocator: Allocator, variable: []const u8) ?[]const u8 {
    var env_map = std.process.getEnvMap(allocator) catch return null;

    var iter = env_map.iterator();
    while (iter.next()) |entry| {
        if (std.mem.eql(u8, entry.key_ptr.*, variable)) return std.fmt.bufPrint(&value_buffer, "{s}", .{entry.value_ptr.*}) catch return null;
    }

    return null;
}

pub fn runQuery(self: *Self, null_term_query_str: [:0]const u8) void {
    var parser = ziqlParser.init(&self.file_engine, &self.schema_engine);
    parser.parse(self.allocator, null_term_query_str) catch |err| log.err("Error parsing: {any}", .{err});
}

pub fn deinit(self: *Self) void {
    self.thread_engine.deinit();
    self.schema_engine.deinit();
    self.file_engine.deinit();
}
