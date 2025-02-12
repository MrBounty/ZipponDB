const std = @import("std");
const dtype = @import("dtype");
const s2t = dtype.s2t;
const UUID = dtype.UUID;
const Allocator = std.mem.Allocator;
const Token = @import("../tokenizer.zig").Token;
const Filter = @import("../../dataStructure/filter.zig").Filter;
const ConditionValue = @import("../../dataStructure/filter.zig").ConditionValue;
const AdditionalData = @import("../../dataStructure/additionalData.zig").AdditionalData;
const printError = @import("../../utils.zig").printError;

const ZipponError = @import("error").ZipponError;

var buff: [1024]u8 = undefined;

var zero_map_buf: [200]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&zero_map_buf);
var zero_map = std.AutoHashMap(UUID, void).init(fba.allocator());
var empty_map = std.AutoHashMap(UUID, void).init(fba.allocator());

const Self = @import("../parser.zig");

pub fn initZeroMap() ZipponError!void {
    zero_map.put(dtype.Zero, {}) catch return ZipponError.MemoryError;
}

/// To run just after a condition like = or > or >= to get the corresponding ConditionValue that you need to compare
pub fn parseConditionValue(
    self: Self,
    allocator: Allocator,
    struct_name: []const u8,
    member_name: []const u8,
    data_type: dtype.DataType,
    token: *Token,
) ZipponError!ConditionValue {
    const start_index = token.loc.start;

    if (data_type.is_array() and data_type != .link_array) switch (token.tag) {
        .l_bracket => token.* = self.toker.next(),
        else => return printError(
            "Error: expecting [ to start array.",
            ZipponError.SynthaxError,
            self.toker.buffer,
            token.loc.start,
            token.loc.end,
        ),
    };

    switch (data_type) {
        .self => unreachable,

        .int => if (token.tag != .int_literal) {
            return printError(
                "Error: Wrong type. Expected: int.",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            );
        } else {
            return ConditionValue.initInt(self.toker.buffer[start_index..token.loc.end]);
        },

        .float => if (token.tag != .float_literal) {
            return printError(
                "Error: Wrong type. Expected: float.",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            );
        } else {
            return ConditionValue.initFloat(self.toker.buffer[start_index..token.loc.end]);
        },

        .str => if (token.tag != .string_literal) {
            return printError(
                "Error: Wrong type. Expected: string.",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            );
        } else {
            return ConditionValue.initStr(self.toker.buffer[start_index + 1 .. token.loc.end - 1]); // Removing ''
        },

        .bool => if (token.tag != .bool_literal_true and token.tag != .bool_literal_false) {
            return printError(
                "Error: Wrong type. Expected: bool.",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            );
        } else {
            return ConditionValue.initBool(self.toker.buffer[start_index..token.loc.end]);
        },

        .date => if (token.tag != .date_literal and token.tag != .keyword_now) {
            return printError(
                "Error: Wrong type. Expected: date.",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            );
        } else {
            return ConditionValue.initDate(self.toker.buffer[start_index..token.loc.end]);
        },

        .time => if (token.tag != .time_literal and token.tag != .keyword_now) {
            return printError(
                "Error: Wrong type. Expected: time.",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            );
        } else {
            return ConditionValue.initTime(self.toker.buffer[start_index..token.loc.end]);
        },

        .datetime => if (token.tag != .date_literal and token.tag != .datetime_literal and token.tag != .keyword_now) {
            return printError(
                "Error: Wrong type. Expected: datetime.",
                ZipponError.SynthaxError,
                self.toker.buffer,
                token.loc.start,
                token.loc.end,
            );
        } else {
            return ConditionValue.initDateTime(self.toker.buffer[start_index..token.loc.end]);
        },

        .int_array => {
            var array = std.ArrayList(i32).init(allocator);
            errdefer array.deinit();

            var first = true;
            while (token.tag != .r_bracket) : (token.* = self.toker.next()) {
                if (!first) {
                    if (token.tag != .comma) return printError(
                        "Error: Expected comma.",
                        ZipponError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );
                    token.* = self.toker.next();
                } else first = false;

                if (token.tag == .int_literal) array.append(s2t.parseInt(self.toker.getTokenSlice(token.*))) catch return ZipponError.MemoryError;
                if (token.tag == .int_literal or token.tag == .comma) continue;
                if (token.tag == .r_bracket) break;
                return printError(
                    "Error: Wrong type. Expected int.",
                    ZipponError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                );
            }

            return try ConditionValue.initArrayInt(array.toOwnedSlice() catch return ZipponError.MemoryError);
        },

        .float_array => {
            var array = std.ArrayList(f64).init(allocator);
            errdefer array.deinit();

            var first = true;
            while (token.tag != .r_bracket) : (token.* = self.toker.next()) {
                if (!first) {
                    if (token.tag != .comma) return printError(
                        "Error: Expected comma.",
                        ZipponError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );
                    token.* = self.toker.next();
                } else first = false;

                if (token.tag == .float_literal) array.append(s2t.parseFloat(self.toker.getTokenSlice(token.*))) catch return ZipponError.MemoryError;
                if (token.tag == .float_literal or token.tag == .comma) continue;
                if (token.tag == .r_bracket) break;
                return printError(
                    "Error: Wrong type. Expected float.",
                    ZipponError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                );
            }

            return try ConditionValue.initArrayFloat(array.toOwnedSlice() catch return ZipponError.MemoryError);
        },

        .bool_array => {
            var array = std.ArrayList(bool).init(allocator);
            errdefer array.deinit();

            var first = true;
            while (token.tag != .r_bracket) : (token.* = self.toker.next()) {
                if (!first) {
                    if (token.tag != .comma) return printError(
                        "Error: Expected comma.",
                        ZipponError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );
                    token.* = self.toker.next();
                } else first = false;

                if (token.tag == .bool_literal_false or token.tag == .bool_literal_false) array.append(s2t.parseBool(self.toker.getTokenSlice(token.*))) catch return ZipponError.MemoryError;
                if (token.tag == .bool_literal_false or token.tag == .bool_literal_false or token.tag == .comma) continue;
                if (token.tag == .r_bracket) break;
                return printError(
                    "Error: Wrong type. Expected bool.",
                    ZipponError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                );
            }

            return try ConditionValue.initArrayBool(array.toOwnedSlice() catch return ZipponError.MemoryError);
        },

        .str_array => {
            var array = std.ArrayList([]const u8).init(allocator);
            errdefer array.deinit();

            var first = true;
            while (token.tag != .r_bracket) : (token.* = self.toker.next()) {
                if (!first) {
                    if (token.tag != .comma) return printError(
                        "Error: Expected comma.",
                        ZipponError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );
                    token.* = self.toker.next();
                } else first = false;

                if (token.tag == .string_literal) array.append(
                    self.toker.getTokenSlice(token.*)[1 .. (token.loc.end - token.loc.start) - 1],
                ) catch return ZipponError.MemoryError;
                if (token.tag == .string_literal or token.tag == .comma) continue;
                if (token.tag == .r_bracket) break;
                return printError(
                    "Error: Wrong type. Expected str.",
                    ZipponError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                );
            }

            return try ConditionValue.initArrayStr(array.toOwnedSlice() catch return ZipponError.MemoryError);
        },

        .date_array => {
            var array = std.ArrayList(u64).init(allocator);
            errdefer array.deinit();

            var first = true;
            while (token.tag != .r_bracket) : (token.* = self.toker.next()) {
                if (!first) {
                    if (token.tag != .comma) return printError(
                        "Error: Expected comma.",
                        ZipponError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );
                    token.* = self.toker.next();
                } else first = false;

                if (token.tag == .date_literal or token.tag == .keyword_now) array.append(s2t.parseDate(self.toker.getTokenSlice(token.*)).toUnix()) catch return ZipponError.MemoryError;
                if (token.tag == .date_literal or token.tag == .keyword_now or token.tag == .comma) continue;
                if (token.tag == .r_bracket) break;
                return printError(
                    "Error: Wrong type. Expected date.",
                    ZipponError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                );
            }

            return try ConditionValue.initArrayUnix(array.toOwnedSlice() catch return ZipponError.MemoryError);
        },

        .time_array => {
            var array = std.ArrayList(u64).init(allocator);
            errdefer array.deinit();

            var first = true;
            while (token.tag != .r_bracket) : (token.* = self.toker.next()) {
                if (!first) {
                    if (token.tag != .comma) return printError(
                        "Error: Expected comma.",
                        ZipponError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );
                    token.* = self.toker.next();
                } else first = false;

                if (token.tag == .time_literal or token.tag == .keyword_now) array.append(s2t.parseTime(self.toker.getTokenSlice(token.*)).toUnix()) catch return ZipponError.MemoryError;
                if (token.tag == .time_literal or token.tag == .keyword_now or token.tag == .comma) continue;
                if (token.tag == .r_bracket) break;
                return printError(
                    "Error: Wrong type. Expected time.",
                    ZipponError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                );
            }

            return try ConditionValue.initArrayUnix(array.toOwnedSlice() catch return ZipponError.MemoryError);
        },

        .datetime_array => {
            var array = std.ArrayList(u64).init(allocator);
            errdefer array.deinit();

            var first = true;
            while (token.tag != .r_bracket) : (token.* = self.toker.next()) {
                if (!first) {
                    if (token.tag != .comma) return printError(
                        "Error: Expected comma.",
                        ZipponError.SynthaxError,
                        self.toker.buffer,
                        token.loc.start,
                        token.loc.end,
                    );
                    token.* = self.toker.next();
                } else first = false;

                if (token.tag == .datetime_literal or token.tag == .date_literal or token.tag == .keyword_now) array.append(s2t.parseDatetime(self.toker.getTokenSlice(token.*)).toUnix()) catch return ZipponError.MemoryError;
                if (token.tag == .datetime_literal or token.tag == .date_literal or token.tag == .keyword_now or token.tag == .comma) continue;
                if (token.tag == .r_bracket) break;
                return printError(
                    "Error: Wrong type. Expected datetime.",
                    ZipponError.SynthaxError,
                    self.toker.buffer,
                    token.loc.start,
                    token.loc.end,
                );
            }

            return try ConditionValue.initArrayUnix(array.toOwnedSlice() catch return ZipponError.MemoryError);
        },

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
                _ = self.toker.next();
                return ConditionValue.initArrayLink(&empty_map);
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
    }
}
