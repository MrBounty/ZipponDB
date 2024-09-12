const std = @import("std");
const Allocator = std.mem.Allocator;
const cliTokenizer = @import("tokenizers/cliTokenizer.zig").Tokenizer;
const cliToken = @import("tokenizers/cliTokenizer.zig").Token;
const schemaTokenizer = @import("tokenizers/schemaTokenizer.zig").Tokenizer;
const schemaToken = @import("tokenizers/schemaTokenizer.zig").Token;
const schemaParser = @import("parsers/schemaParser.zig").Parser;

pub fn main() !void {
    checkAndCreateDirectories();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    while (true) {
        std.debug.print("> ", .{});
        var line_buf: [1024]u8 = undefined;
        const line = try std.io.getStdIn().reader().readUntilDelimiterOrEof(&line_buf, '\n');

        if (line) |line_str| {
            const null_term_line_str = try allocator.dupeZ(u8, line_str[0..line_str.len]);

            var cliToker = cliTokenizer.init(null_term_line_str);
            const command_token = cliToker.next();
            switch (command_token.tag) {
                .keyword_run => {
                    const query_token = cliToker.next();
                    switch (query_token.tag) {
                        .string_literal => {
                            const null_term_query_str = try allocator.dupeZ(u8, line_str[query_token.loc.start + 1 .. query_token.loc.end - 1]);
                            runCommand(null_term_query_str);
                        },
                        else => {
                            std.debug.print("After command run, need a string of a query, eg: \"GRAB User\"\n", .{});
                            continue;
                        },
                    }
                },
                .keyword_schema => {
                    const second_token = cliToker.next();

                    switch (second_token.tag) {
                        .keyword_describe => {
                            runCommand("__DESCRIBE__");
                        },
                        .keyword_build => {
                            const file_name_token = cliToker.next();
                            var file_name = try allocator.alloc(u8, 1024);
                            var len: usize = 0;

                            switch (file_name_token.tag) {
                                .eof => {
                                    std.mem.copyForwards(u8, file_name, "schema.zipponschema");
                                    len = 19;
                                },
                                else => file_name = line_str[file_name_token.loc.start..file_name_token.loc.end],
                            }

                            std.debug.print("{s}", .{file_name[0..len]});

                            //blk: {
                            //createDtypeFile(file_name[0..len]) catch |err| switch (err) {
                            //    error.FileNotFound => {
                            //        std.debug.print("Error: Can't find file: {s}\n", .{file_name[0..len]});
                            //        break :blk;
                            //    },
                            //    else => {
                            //        std.debug.print("Error: Unknow error when creating Dtype file: {any}\n", .{err});
                            //        break :blk;
                            //    },
                            //};
                            try buildEngine();
                            //}
                            allocator.free(file_name);
                        },
                        .keyword_help => {
                            std.debug.print("{s}", .{
                                \\Here are all available options to use with the schema command:
                                \\
                                \\describe  Print the schema use by the current engine.
                                \\build     Build a new engine using a schema file. Args => filename: str, path of schema file to use. Default 'schema.zipponschema'.
                                \\
                            });
                        },
                        else => {
                            std.debug.print("schema available options: describe, build & help\n", .{});
                        },
                    }
                },
                .keyword_help => {
                    std.debug.print("{s}", .{
                        \\Welcome to ZipponDB!
                        \\
                        \\run       To run a query. Args => query: str, the query to execute.
                        \\schema    Build a new engine and print current schema.
                        \\kill      To stop the process without saving
                        \\save      Save the database to the normal files.
                        \\dump      Create a new folder with all data as copy. Args => foldername: str, the name of the folder.
                        \\bump      Replace current data with a previous dump. Args => foldername: str, the name of the folder.
                        \\
                    });
                },
                .keyword_quit => {
                    break;
                },
                .eof => {},
                else => {
                    std.debug.print("Command need to start with a keyword, including: run, schema, help and quit\n", .{});
                },
            }
        }
    }
}

fn createDtypeFile(file_path: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const cwd = std.fs.cwd();
    var file = try cwd.openFile(file_path, .{
        .mode = .read_only,
    });
    defer file.close();

    const buffer = try file.readToEndAlloc(allocator, 1024);
    const file_contents = try allocator.dupeZ(u8, buffer[0..]); // Duplicate to a null terminated string

    var schemaToker = schemaTokenizer.init(file_contents);
    var parser = schemaParser.init();
    parser.parse(&schemaToker, buffer);

    // Free memory
    allocator.free(buffer);
    allocator.free(file_contents);
    const check = gpa.deinit();
    switch (check) {
        .ok => return,
        .leak => std.debug.print("Error: Leak in createDtypeFile!\n", .{}),
    }
}

fn buildEngine() !void {
    const argv = &[_][]const u8{
        "zig",
        "build-exe",
        "src/dbengine.zig",
        "--name",
        "engine",
    };

    var child = std.process.Child.init(argv, std.heap.page_allocator);
    try child.spawn();
    _ = try child.wait();

    const dtypes = @import("dtypes.zig");

    const data_dir = try std.fs.cwd().openDir("ZipponDB/DATA", .{});
    for (dtypes.struct_name_list) |struct_name| {
        data_dir.makeDir(struct_name) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => @panic("Error other than path already exists when trying to create a struct directory.\n"),
        };
        const struct_dir = try data_dir.openDir(struct_name, .{});

        const member_names = dtypes.structName2structMembers(struct_name);
        for (member_names) |member_name| {
            struct_dir.makeDir(member_name) catch |err| switch (err) {
                error.PathAlreadyExists => return,
                else => @panic("Error other than path already exists when trying to create a member directory.\n"),
            };
            const member_dir = try struct_dir.openDir(member_name, .{});

            blk: {
                const file = member_dir.createFile("main.zippondata", .{}) catch |err| switch (err) {
                    error.PathAlreadyExists => break :blk,
                    else => @panic("Error: can't create main.zippondata"),
                };
                try file.writeAll("\n");
            }
            _ = member_dir.createFile("1.zippondata", .{}) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => @panic("Error: can't create 1.zippondata"),
            };
        }
    }
}

fn runCommand(null_term_query_str: [:0]const u8) void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const argv = &[_][]const u8{ "./engine", null_term_query_str };

    const result = std.process.Child.run(.{ .allocator = allocator, .argv = argv }) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("No engine found, please use `schema build` to make one.\n", .{});
            return;
        },
        else => {
            std.debug.print("Error: Unknow error when trying to run the engine: {any}\n", .{err});
            return;
        },
    };
    switch (result.term) {
        .Exited => {},
        .Signal => std.debug.print("Error: term signal in runCommand\n", .{}),
        .Stopped => std.debug.print("Error: term stopped in runCommand\n", .{}),
        .Unknown => std.debug.print("Error: term unknow in runCommand\n", .{}),
    }

    std.debug.print("{s}\n", .{result.stdout});

    allocator.free(result.stdout);
    allocator.free(result.stderr);

    const check = gpa.deinit();
    switch (check) {
        .ok => return,
        .leak => std.debug.print("Error: Leak in runCommand!\n", .{}),
    }
}

fn checkAndCreateDirectories() void {
    const cwd = std.fs.cwd();

    cwd.makeDir("ZipponDB") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => @panic("Error other than path already exists when trying to create the ZipponDB directory.\n"),
    };

    cwd.makeDir("ZipponDB/DATA") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => @panic("Error other than path already exists when trying to create the DATA directory.\n"),
    };

    cwd.makeDir("ZipponDB/ENGINE") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => @panic("Error other than path already exists when trying to create the ENGINE directory.\n"),
    };
}
