const std = @import("std");
const Allocator = std.mem.Allocator;
const Toker = @import("../tokenizers/schemaTokenizer.zig").Tokenizer;
const Token = @import("../tokenizers/schemaTokenizer.zig").Token;

pub const Parser = struct {
    file: std.fs.File,

    const State = enum {
        start,
        invalid,

        expect_l_paren,
        expect_r_paren,
        expect_member_name,
        expect_two_dot,
        expect_value_type,
        expect_comma,
    };

    pub fn init() Parser {
        return .{
            .file = undefined,
        };
    }

    fn writeToFile(self: *const Parser, text: []const u8) void {
        const bytes_written = self.file.write(text) catch |err| {
            std.debug.print("Error when writing dtypes.zig: {}", .{err});
            return;
        };
        _ = bytes_written;
    }

    pub fn parse(self: *Parser, toker: *Toker, buffer: []u8) void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();
        var struct_array = std.ArrayList([]u8).init(allocator);

        var state: State = .start;

        std.fs.cwd().deleteFile("src/dtypes.zig") catch {};

        self.file = std.fs.cwd().createFile("src/dtypes.zig", .{}) catch |err| {
            std.debug.print("Error when writing dtypes.zig: {}", .{err});
            return;
        };
        defer self.file.close();

        self.writeToFile("const std = @import(\"std\");\nconst UUID = @import(\"uuid.zig\").UUID;\n\n");

        var token = toker.next();
        while (token.tag != Token.Tag.eof) : (token = toker.next()) {
            switch (state) {
                .start => switch (token.tag) {
                    .identifier => {
                        state = .expect_l_paren;
                        self.writeToFile("pub const ");
                        self.writeToFile(buffer[token.loc.start..token.loc.end]);
                        self.writeToFile(" = struct {\n");
                        self.writeToFile("    id: UUID,\n");

                        // TODO: Check if struct name is already use
                        struct_array.append(buffer[token.loc.start..token.loc.end]) catch @panic("Error appending a struct name.");
                    },
                    else => {
                        state = .invalid;
                    },
                },
                .expect_l_paren => switch (token.tag) {
                    .l_paren => {
                        state = .expect_member_name;
                    },
                    else => {
                        state = .invalid;
                    },
                },
                .expect_member_name => switch (token.tag) {
                    .identifier => {
                        state = .expect_two_dot;
                        self.writeToFile("    ");
                        self.writeToFile(buffer[token.loc.start..token.loc.end]);
                    },
                    .r_paren => {
                        state = .start;
                        self.writeToFile("};\n\n");
                    },
                    else => {
                        state = .invalid;
                    },
                },
                .expect_two_dot => switch (token.tag) {
                    .two_dot => {
                        state = .expect_value_type;
                        self.writeToFile(": ");
                    },
                    else => {
                        state = .invalid;
                    },
                },
                .expect_value_type => switch (token.tag) {
                    .type_int => {
                        state = .expect_comma;
                        self.writeToFile("i64");
                    },
                    .type_str => {
                        state = .expect_comma;
                        self.writeToFile("[] u8");
                    },
                    .type_float => {
                        state = .expect_comma;
                        self.writeToFile("f64");
                    },
                    .type_date => {
                        @panic("Date not yet implemented");
                    },
                    .identifier => {
                        @panic("Link not yet implemented");
                    },
                    .lr_bracket => {
                        @panic("Array not yet implemented");
                    },
                    else => {
                        state = .invalid;
                    },
                },
                .expect_comma => switch (token.tag) {
                    .comma => {
                        state = .expect_member_name;
                        self.writeToFile(",\n");
                    },
                    else => {
                        state = .invalid;
                    },
                },
                .invalid => {
                    // TODO: Better errors
                    @panic("Error: Schema need to start with an Identifier.");
                },
                else => {
                    @panic("");
                },
            }
        }

        // Use @embedFile

        // Make the union `Type` with all different struct
        self.writeToFile("pub const Types = union {\n");
        for (struct_array.items) |struct_name| {
            self.writeToFile("    ");
            self.writeToFile(struct_name);
            self.writeToFile(": *");
            self.writeToFile(struct_name);
            self.writeToFile(",\n");
        }
        self.writeToFile("};\n\n");

        // Make an array of struct name
        self.writeToFile("pub const struct_name_list: [");
        var int_buffer: [20]u8 = undefined;
        const len = std.fmt.formatIntBuf(&int_buffer, @as(usize, struct_array.items.len), 10, .lower, .{});
        self.writeToFile(int_buffer[0..len]);
        self.writeToFile("][]const u8 = .{ ");
        for (struct_array.items) |struct_name| {
            self.writeToFile(" \"");
            self.writeToFile(struct_name);
            self.writeToFile("\", ");
        }
        self.writeToFile("};\n\n");

        // Create the var that contain the description of the current schema to be printed when running:
        // The query "__DESCRIBE__" on the engine
        // Or the command `schema describe` on the console
        self.writeToFile("pub const describe_str = \"");
        var escaped_text: [1024]u8 = undefined;
        const replacement_count = std.mem.replace(u8, buffer, "\n", "\\n", &escaped_text);
        const escaped_text_len = replacement_count + buffer.len;
        self.writeToFile(escaped_text[0..escaped_text_len]);
        self.writeToFile("\";");
    }
};
