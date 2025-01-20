const std = @import("std");
const Allocator = std.mem.Allocator;
const FileEngine = @import("../file/core.zig");
const SchemaEngine = @import("../schema/core.zig");
const Tokenizer = @import("tokenizer.zig").Tokenizer;

const dtype = @import("dtype");
const UUID = dtype.UUID;

const ValueOrArray = @import("parts/newData.zig").ValueOrArray;
const AdditionalData = @import("../dataStructure/additionalData.zig").AdditionalData;
const send = @import("../utils.zig").send;
const printError = @import("../utils.zig").printError;

const ZipponError = @import("error").ZipponError;
const PRINT_STATE = @import("config").PRINT_STATE;

const log = std.log.scoped(.ziqlParser);

pub const State = enum {
    start,
    invalid,
    end,

    // Endpoint
    parse_new_data_and_add_data,
    filter_and_send,
    filter_and_update,
    filter_and_delete,

    // For the main parse function
    expect_struct_name,
    expect_filter,
    parse_additional_data,
    expect_filter_or_additional_data,
    expect_new_data,
    expect_right_arrow,

    // For the additional data parser
    expect_limit,
    expect_semicolon_OR_right_bracket,
    expect_member,
    expect_comma_OR_r_bracket_OR_l_bracket,
    expect_comma_OR_r_bracket,

    // For the filter parser
    expect_condition,
    expect_operation, // Operations are = != < <= > >=
    expect_value,
    expect_ANDOR_OR_end,
    expect_right_uuid_array,

    // For the new data
    expect_member_OR_value,
    expect_equal,
    expect_new_value,
    expect_comma_OR_end,
    add_member_to_map,
    add_array_to_map,
};

pub const Self = @This();

pub usingnamespace @import("parts/comparison.zig");
pub usingnamespace @import("parts/condition.zig");
pub usingnamespace @import("parts/newData.zig");
pub usingnamespace @import("parts/value.zig");
pub usingnamespace @import("parts/filter.zig");
pub usingnamespace @import("parts/additionalData.zig");
pub usingnamespace @import("utils.zig");

toker: *Tokenizer = undefined,
file_engine: *FileEngine,
schema_engine: *SchemaEngine,

pub fn init(file_engine: *FileEngine, schema_engine: *SchemaEngine) Self {
    return Self{
        .file_engine = file_engine,
        .schema_engine = schema_engine,
    };
}

pub fn parse(self: *Self, buffer: [:0]const u8) ZipponError!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try @import("parts/value.zig").initZeroMap();

    var toker = Tokenizer.init(buffer);
    self.toker = &toker;

    var state: State = .start;
    var additional_data = AdditionalData.init(allocator);
    var struct_name: []const u8 = undefined;
    var action: enum { GRAB, ADD, UPDATE, DELETE } = undefined;

    var token = self.toker.next();
    var keep_next = false; // Use in the loop to prevent to get the next token when continue. Just need to make it true and it is reset at every loop

    while (state != State.end) : ({
        token = if (!keep_next) self.toker.next() else token;
        keep_next = false;
        if (PRINT_STATE) std.debug.print("parse: {any}\n", .{state});
    }) switch (state) {
        .start => switch (token.tag) {
            .keyword_grab => {
                action = .GRAB;
                state = .expect_struct_name;
            },
            .keyword_add => {
                action = .ADD;
                state = .expect_struct_name;
            },
            .keyword_update => {
                action = .UPDATE;
                state = .expect_struct_name;
            },
            .keyword_delete => {
                action = .DELETE;
                state = .expect_struct_name;
            },
            else => return printError(
                "Error: Expected action keyword. Available: GRAB ADD DELETE UPDATE",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },

        .expect_struct_name => {
            // Check if the struct name is in the schema
            struct_name = self.toker.getTokenSlice(token);
            if (token.tag != .identifier) return printError(
                "Error: Missing struct name.",
                ZipponError.StructNotFound,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            );
            if (!self.schema_engine.isStructNameExists(struct_name)) return printError(
                "Error: struct name not found in schema.",
                ZipponError.StructNotFound,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            );
            switch (action) {
                .ADD => state = .expect_new_data,
                else => state = .expect_filter_or_additional_data,
            }
        },

        .expect_filter_or_additional_data => {
            keep_next = true;
            switch (token.tag) {
                .l_bracket => state = .parse_additional_data,
                .l_brace, .eof => state = switch (action) {
                    .GRAB => .filter_and_send,
                    .UPDATE => .filter_and_update,
                    .DELETE => .filter_and_delete,
                    else => unreachable,
                },
                else => return printError(
                    "Error: Expect [ for additional data or { for a filter",
                    ZipponError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                ),
            }
        },

        .parse_additional_data => {
            try self.parseAdditionalData(allocator, &additional_data, struct_name);
            state = switch (action) {
                .GRAB => .filter_and_send,
                .UPDATE => .filter_and_update,
                .DELETE => .filter_and_delete,
                else => unreachable,
            };
        },

        .filter_and_send => switch (token.tag) {
            .l_brace => {
                var filter = try self.parseFilter(allocator, struct_name, false);
                defer filter.deinit();

                const json_string = try self.file_engine.parseEntities(struct_name, filter, &additional_data, allocator);
                send("{s}", .{json_string});
                state = .end;
            },
            .eof => {
                const json_string = try self.file_engine.parseEntities(struct_name, null, &additional_data, allocator);
                send("{s}", .{json_string});
                state = .end;
            },
            else => return printError(
                "Error: Expected filter.",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },

        .filter_and_update => switch (token.tag) {
            .l_brace => {
                var filter = try self.parseFilter(allocator, struct_name, false);
                defer filter.deinit();

                token = self.toker.last();

                if (token.tag != .keyword_to) return printError(
                    "Error: Expected TO",
                    ZipponError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                );

                token = self.toker.next();
                if (token.tag != .l_paren) return printError(
                    "Error: Expected (",
                    ZipponError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                );

                const sstruct = try self.schema_engine.structName2SchemaStruct(struct_name);
                var members = std.ArrayList([]const u8).init(allocator);
                defer members.deinit();
                members.appendSlice(sstruct.members[1..]) catch return ZipponError.MemoryError;

                var data_map = std.StringHashMap(ValueOrArray).init(allocator);
                defer data_map.deinit();
                try self.parseNewData(allocator, &data_map, struct_name, &members, true);

                var buff = std.ArrayList(u8).init(allocator);
                defer buff.deinit();

                try self.file_engine.updateEntities(struct_name, filter, data_map, &buff.writer(), &additional_data);
                send("{s}", .{buff.items});
                state = .end;
            },
            .keyword_to => {
                token = self.toker.next();
                if (token.tag != .l_paren) return printError(
                    "Error: Expected (",
                    ZipponError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                );

                const sstruct = try self.schema_engine.structName2SchemaStruct(struct_name);
                var members = std.ArrayList([]const u8).init(allocator);
                defer members.deinit();
                members.appendSlice(sstruct.members[1..]) catch return ZipponError.MemoryError;

                var data_map = std.StringHashMap(ValueOrArray).init(allocator);
                defer data_map.deinit();
                try self.parseNewData(allocator, &data_map, struct_name, &members, true);

                var buff = std.ArrayList(u8).init(allocator);
                defer buff.deinit();

                try self.file_engine.updateEntities(struct_name, null, data_map, &buff.writer(), &additional_data);
                send("{s}", .{buff.items});
                state = .end;
            },
            else => return printError(
                "Error: Expected filter or TO.",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },

        .filter_and_delete => switch (token.tag) {
            .l_brace => {
                var filter = try self.parseFilter(allocator, struct_name, false);
                defer filter.deinit();

                var buff = std.ArrayList(u8).init(allocator);
                defer buff.deinit();

                try self.file_engine.deleteEntities(struct_name, filter, &buff.writer(), &additional_data);
                send("{s}", .{buff.items});
                state = .end;
            },
            .eof => {
                var buff = std.ArrayList(u8).init(allocator);
                defer buff.deinit();

                try self.file_engine.deleteEntities(struct_name, null, &buff.writer(), &additional_data);
                send("{s}", .{buff.items});
                state = .end;
            },
            else => return printError(
                "Error: Expected filter.",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },

        .expect_new_data => switch (token.tag) {
            .l_paren => {
                keep_next = true;
                state = .parse_new_data_and_add_data;
            },
            else => return printError(
                "Error: Expected new data starting with (",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },

        .parse_new_data_and_add_data => {
            const sstruct = try self.schema_engine.structName2SchemaStruct(struct_name);
            var order = std.ArrayList([]const u8).init(allocator);
            defer order.deinit();
            order.appendSlice(sstruct.members[1..]) catch return ZipponError.MemoryError;

            var buff = std.ArrayList(u8).init(allocator);
            defer buff.deinit();
            buff.writer().writeAll("[") catch return ZipponError.WriteError;

            var maps = std.ArrayList(std.StringHashMap(ValueOrArray)).init(allocator);
            defer maps.deinit();

            var local_arena = std.heap.ArenaAllocator.init(allocator);
            defer local_arena.deinit();
            const local_allocator = arena.allocator();

            var data_map = std.StringHashMap(ValueOrArray).init(allocator);
            defer data_map.deinit();

            while (true) { // I could multithread that as it do take a long time for big benchmark
                data_map.clearRetainingCapacity();
                try self.parseNewData(local_allocator, &data_map, struct_name, &order, false);

                var error_message_buffer = std.ArrayList(u8).init(local_allocator);
                defer error_message_buffer.deinit();

                const error_message_buffer_writer = error_message_buffer.writer();
                error_message_buffer_writer.writeAll("Error missing: ") catch return ZipponError.WriteError;

                if (!(self.schema_engine.checkIfAllMemberInMap(struct_name, &data_map, &error_message_buffer) catch {
                    return ZipponError.StructNotFound;
                })) {
                    _ = error_message_buffer.pop();
                    _ = error_message_buffer.pop();
                    return printError(
                        error_message_buffer.items,
                        ZipponError.MemberMissing,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );
                }

                maps.append(data_map.cloneWithAllocator(local_allocator) catch return ZipponError.MemoryError) catch return ZipponError.MemoryError;

                if (maps.items.len >= 1_000) {
                    try self.file_engine.addEntity(struct_name, maps.items, &buff.writer());
                    maps.clearRetainingCapacity();
                    _ = local_arena.reset(.retain_capacity);
                }

                token = self.toker.last_token;
                if (token.tag == .l_paren) continue;
                break;
            }

            try self.file_engine.addEntity(struct_name, maps.items, &buff.writer());

            buff.writer().writeAll("]") catch return ZipponError.WriteError;
            send("{s}", .{buff.items});
            state = .end;
        },

        else => unreachable,
    };
}
