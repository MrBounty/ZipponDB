const std = @import("std");
const dtype = @import("dtype");
const UUID = dtype.UUID;
const Allocator = std.mem.Allocator;
const Token = @import("../tokenizer.zig").Token;
const Filter = @import("../../dataStructure/filter.zig").Filter;
const ConditionValue = @import("../../dataStructure/filter.zig").ConditionValue;
const AdditionalData = @import("../../dataStructure/additionalData.zig").AdditionalData;
const printError = @import("../../utils.zig").printError;

const ZipponError = @import("error").ZipponError;

var buff: [1024]u8 = undefined;

var zero_map_buf: [1024 * 4]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&zero_map_buf);
var zero_map = std.AutoHashMap(UUID, void).init(fba.allocator());

const Self = @import("../parser.zig");

pub fn initZeroMap() ZipponError!void {
    zero_map.put(dtype.Zero, {}) catch return ZipponError.MemoryError;
}

/// To run just after a condition like = or > or >= to get the corresponding ConditionValue that you need to compare
pub fn parseConditionValue(self: Self, allocator: Allocator, struct_name: []const u8, member_name: []const u8, data_type: dtype.DataType, token: *Token) ZipponError!ConditionValue {
    const start_index = token.loc.start;
    const expected_tag: ?Token.Tag = switch (data_type) {
        .int => .int_literal,
        .float => .float_literal,
        .str => .string_literal,
        .self => .uuid_literal,
        .int_array => .int_literal,
        .float_array => .float_literal,
        .str_array => .string_literal,
        .bool, .bool_array, .link, .link_array, .date, .time, .datetime, .date_array, .time_array, .datetime_array => null, // handle separately
    };

    // Check if the all next tokens are the right one
    if (expected_tag) |tag| {
        if (data_type.is_array()) {
            token.* = try self.checkTokensInArray(tag);
        } else {
            if (token.tag != tag) {
                const msg = std.fmt.bufPrint(&buff, "Error: Wrong type. Expected: {any}", .{tag}) catch return ZipponError.MemoryError;
                return printError(
                    msg,
                    ZipponError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                );
            }
        }
    } else switch (data_type) {
        .bool => if (token.tag != .bool_literal_true and token.tag != .bool_literal_false) {
            return printError(
                "Error: Expected bool",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            );
        },
        .bool_array => {
            token.* = self.toker.next();
            while (token.tag != .r_bracket) : (token.* = self.toker.next()) {
                if (token.tag != .bool_literal_true and token.tag != .bool_literal_false) {
                    return printError(
                        "Error: Expected bool or ]",
                        ZipponError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );
                }
            }
        },
        .date => if (token.tag != .date_literal and token.tag != .keyword_now) {
            return printError(
                "Error: Expected date",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            );
        },
        .date_array => {
            token.* = self.toker.next();
            while (token.tag != .r_bracket) : (token.* = self.toker.next()) {
                if (token.tag != .date_literal and token.tag != .keyword_now) {
                    return printError(
                        "Error: Expected date",
                        ZipponError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );
                }
            }
        },
        .time => if (token.tag != .time_literal and token.tag != .keyword_now) {
            return printError(
                "Error: Expected time",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            );
        },
        .time_array => {
            token.* = self.toker.next();
            while (token.tag != .r_bracket) : (token.* = self.toker.next()) {
                if (token.tag != .time_literal and token.tag != .keyword_now) {
                    return printError(
                        "Error: Expected time",
                        ZipponError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );
                }
            }
        },
        .datetime => if (token.tag != .datetime_literal and token.tag != .keyword_now) {
            return printError(
                "Error: Expected datetime",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            );
        },
        .datetime_array => {
            token.* = self.toker.next();
            while (token.tag != .r_bracket) : (token.* = self.toker.next()) {
                if (token.tag != .datetime_literal and token.tag != .keyword_now) {
                    return printError(
                        "Error: Expected datetime",
                        ZipponError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );
                }
            }
        },
        .link, .link_array => {},
        else => unreachable,
    }

    // And finally create the ConditionValue
    switch (data_type) {
        .int => return ConditionValue.initInt(self.toker.buffer[start_index..token.loc.end]),
        .float => return ConditionValue.initFloat(self.toker.buffer[start_index..token.loc.end]),
        .str => return ConditionValue.initStr(self.toker.buffer[start_index + 1 .. token.loc.end - 1]),
        .date => return ConditionValue.initDate(self.toker.buffer[start_index..token.loc.end]),
        .time => return ConditionValue.initTime(self.toker.buffer[start_index..token.loc.end]),
        .datetime => return ConditionValue.initDateTime(self.toker.buffer[start_index..token.loc.end]),
        .bool => return ConditionValue.initBool(self.toker.buffer[start_index..token.loc.end]),
        .int_array => return try ConditionValue.initArrayInt(allocator, self.toker.buffer[start_index..token.loc.end]),
        .str_array => return try ConditionValue.initArrayStr(allocator, self.toker.buffer[start_index..token.loc.end]),
        .bool_array => return try ConditionValue.initArrayBool(allocator, self.toker.buffer[start_index..token.loc.end]),
        .float_array => return try ConditionValue.initArrayFloat(allocator, self.toker.buffer[start_index..token.loc.end]),
        .date_array => return try ConditionValue.initArrayDate(allocator, self.toker.buffer[start_index..token.loc.end]),
        .time_array => return try ConditionValue.initArrayTime(allocator, self.toker.buffer[start_index..token.loc.end]),
        .datetime_array => return try ConditionValue.initArrayDateTime(allocator, self.toker.buffer[start_index..token.loc.end]),
        .link => switch (token.tag) {
            .keyword_none => {
                _ = self.toker.next();
                return ConditionValue.initLink(&zero_map);
            },
            .uuid_literal => {
                const uuid = UUID.parse(self.toker.buffer[start_index..token.loc.end]) catch return ZipponError.InvalidUUID;
                if (!self.schema_engine.isUUIDExist(struct_name, uuid)) return printError(
                    "Error: UUID do not exist in database.",
                    ZipponError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                );

                const map = allocator.create(std.AutoHashMap(UUID, void)) catch return ZipponError.MemoryError;
                map.* = std.AutoHashMap(UUID, void).init(allocator);
                map.put(uuid, {}) catch return ZipponError.MemoryError;
                _ = self.toker.next();
                return ConditionValue.initLink(map);
            },
            .l_brace, .l_bracket => {
                var filter: ?Filter = null;
                defer if (filter != null) filter.?.deinit();

                var additional_data_arena = std.heap.ArenaAllocator.init(allocator);
                defer additional_data_arena.deinit();
                var additional_data = AdditionalData.init(additional_data_arena.allocator());

                if (token.tag == .l_bracket) {
                    try self.parseAdditionalData(allocator, &additional_data, struct_name);
                    token.* = self.toker.next();
                }

                additional_data.limit = 1;

                const link_sstruct = try self.schema_engine.linkedStructName(struct_name, member_name);
                if (token.tag == .l_brace) filter = try self.parseFilter(
                    allocator,
                    link_sstruct.name,
                    false,
                ) else return printError(
                    "Error: Expected filter",
                    ZipponError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                );

                filter = switch (filter.?.root.*) {
                    .empty => null,
                    else => filter,
                };

                // Here I have the filter and additionalData
                const map = allocator.create(std.AutoHashMap(UUID, void)) catch return ZipponError.MemoryError;
                map.* = std.AutoHashMap(UUID, void).init(allocator);
                try self.file_engine.populateVoidUUIDMap(
                    link_sstruct.name,
                    filter,
                    map,
                    &additional_data,
                );
                return ConditionValue.initLink(map);
            },

            else => return printError(
                "Error: Expected uuid or none",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },
        .link_array => switch (token.tag) {
            .keyword_none => {
                const map = allocator.create(std.AutoHashMap(UUID, void)) catch return ZipponError.MemoryError;
                map.* = std.AutoHashMap(UUID, void).init(allocator);
                _ = self.toker.next();
                return ConditionValue.initArrayLink(map);
            },
            .l_brace, .l_bracket => {
                var filter: ?Filter = null;
                defer if (filter != null) filter.?.deinit();

                var additional_data_arena = std.heap.ArenaAllocator.init(allocator);
                defer additional_data_arena.deinit();
                var additional_data = AdditionalData.init(additional_data_arena.allocator());

                if (token.tag == .l_bracket) {
                    try self.parseAdditionalData(allocator, &additional_data, struct_name);
                    token.* = self.toker.next();
                }

                const link_sstruct = try self.schema_engine.linkedStructName(struct_name, member_name);
                if (token.tag == .l_brace) filter = try self.parseFilter(allocator, link_sstruct.name, false) else return printError(
                    "Error: Expected filter",
                    ZipponError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                );

                filter = switch (filter.?.root.*) {
                    .empty => null,
                    else => filter,
                };

                // Here I have the filter and additionalData
                const map = allocator.create(std.AutoHashMap(UUID, void)) catch return ZipponError.MemoryError;
                map.* = std.AutoHashMap(UUID, void).init(allocator);
                try self.file_engine.populateVoidUUIDMap(
                    struct_name,
                    filter,
                    map,
                    &additional_data,
                );
                return ConditionValue.initArrayLink(map);
            },
            else => return printError(
                "Error: Expected uuid or none",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            ),
        },
        .self => unreachable,
    }
}
