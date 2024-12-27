const std = @import("std");
const utils = @import("stuffs/utils.zig");
const zid = @import("ZipponData");
const AdditionalData = @import("stuffs/additionalData.zig").AdditionalData;
const JsonString = @import("stuffs/relationMap.zig").JsonString;
const dtype = @import("dtype");
const DataType = dtype.DataType;
const DateTime = dtype.DateTime;
const UUID = dtype.UUID;

const ZipponError = @import("stuffs/errors.zig").ZipponError;

// TODO: Try std.json

pub const EntityWriter = struct {
    pub fn writeEntityTable(
        writer: anytype,
        row: []zid.Data,
        additional_data: AdditionalData,
        data_types: []const DataType,
    ) !void {
        try writer.writeAll("| ");
        for (additional_data.childrens.items) |member| {
            try writeValue(writer, row[member.index], data_types[member.index]);
            try writer.writeAll(" \t| ");
        }
        try writer.writeByte('\n');
    }

    pub fn writeEntityJSON(
        writer: anytype,
        row: []zid.Data,
        additional_data: AdditionalData,
        data_types: []const DataType,
    ) !void {
        try writer.writeByte('{');
        for (additional_data.childrens.items) |member| {
            try writer.print("{s}: ", .{member.name});
            try writeValue(writer, row[member.index], data_types[member.index]);
            try writer.writeAll(", ");
        }
        try writer.writeAll("}, ");
    }

    fn writeValue(writer: anytype, value: zid.Data, data_type: DataType) !void {
        switch (value) {
            .Float => |v| try writer.print("{d}", .{v}),
            .Int => |v| try writer.print("{d}", .{v}),
            .Str => |v| try writer.print("\"{s}\"", .{v}),
            .UUID => |v| {
                if (data_type == .self) {
                    try writer.print("\"{s}\"", .{UUID.format_bytes(v)});
                    return;
                }
                const uuid = try UUID.parse("00000000-0000-0000-0000-000000000000"); // Maybe pass that comptime to prevent parsing it everytime
                if (!std.meta.eql(v, uuid.bytes)) {
                    try writer.print("\"{{|<{s}>|}}\"", .{v});
                } else {
                    try writer.print("{{}}", .{});
                }
            },
            .Bool => |v| try writer.print("{any}", .{v}),
            .Unix => |v| {
                const datetime = DateTime.initUnix(v);
                try writer.writeByte('"');
                switch (data_type) {
                    .date => try datetime.format("YYYY/MM/DD", writer),
                    .time => try datetime.format("HH:mm:ss.SSSS", writer),
                    .datetime => try datetime.format("YYYY/MM/DD-HH:mm:ss.SSSS", writer),
                    else => unreachable,
                }
                try writer.writeByte('"');
            },
            .IntArray, .FloatArray, .StrArray, .UUIDArray, .BoolArray, .UnixArray => try writeArray(writer, value, data_type),
        }
    }

    fn writeArray(writer: anytype, data: zid.Data, data_type: DataType) ZipponError!void {
        writer.writeByte('[') catch return ZipponError.WriteError;
        var iter = zid.ArrayIterator.init(data) catch return ZipponError.ZipponDataError;
        switch (data) {
            .IntArray => while (iter.next()) |v| writer.print("{d}, ", .{v.Int}) catch return ZipponError.WriteError,
            .FloatArray => while (iter.next()) |v| writer.print("{d}", .{v.Float}) catch return ZipponError.WriteError,
            .StrArray => while (iter.next()) |v| writer.print("\"{s}\"", .{v.Str}) catch return ZipponError.WriteError,
            .UUIDArray => while (iter.next()) |v| writer.print("\"{{|<{s}>|}}\"", .{UUID.format_bytes(v.UUID)}) catch return ZipponError.WriteError,
            .BoolArray => while (iter.next()) |v| writer.print("{any}", .{v.Bool}) catch return ZipponError.WriteError,
            .UnixArray => while (iter.next()) |v| {
                const datetime = DateTime.initUnix(v.Unix);
                writer.writeByte('"') catch return ZipponError.WriteError;
                switch (data_type) {
                    .date => datetime.format("YYYY/MM/DD", writer) catch return ZipponError.WriteError,
                    .time => datetime.format("HH:mm:ss.SSSS", writer) catch return ZipponError.WriteError,
                    .datetime => datetime.format("YYYY/MM/DD-HH:mm:ss.SSSS", writer) catch return ZipponError.WriteError,
                    else => unreachable,
                }
                writer.writeAll("\", ") catch return ZipponError.WriteError;
            },
            else => unreachable,
        }
        writer.writeByte(']') catch return ZipponError.WriteError;
    }

    /// Take a string in the JSON format and look for {|<[16]u8>|}, then will look into the map and check if it can find this UUID
    /// If it find it, it ill replace the {|<[16]u8>|} will the value
    pub fn updateWithRelation(writer: anytype, input: []const u8, to_add: std.AutoHashMap([16]u8, JsonString)) ZipponError!void {
        var uuid_bytes: [16]u8 = undefined;
        var start: usize = 0;
        while (std.mem.indexOf(u8, input[start..], "{|<[")) |pos| {
            const pattern_start = start + pos;
            const pattern_end = std.mem.indexOf(u8, input[pattern_start..], "]>|}") orelse break;
            const full_pattern_end = pattern_start + pattern_end + 4;

            // Write the text before the pattern
            writer.writeAll(input[start..pattern_start]) catch return ZipponError.WriteError;

            for (pattern_start + 3..pattern_end - 3, 0..) |i, j| uuid_bytes[j] = input[i];
            if (to_add.get(uuid_bytes)) |json_string| {
                writer.writeAll(json_string.slice) catch return ZipponError.WriteError;
            } else {
                writer.writeAll(input[pattern_start..pattern_end]) catch return ZipponError.WriteError;
            }
            start = full_pattern_end;
        }

        // Write any remaining text
        writer.writeAll(input[start..]) catch return ZipponError.WriteError;
    }
};
