const std = @import("std");
const utils = @import("utils.zig");
const zid = @import("ZipponData");
const AdditionalData = @import("../dataStructure/additionalData.zig").AdditionalData;
const JsonString = @import("../dataStructure/relationMap.zig").JsonString;
const dtype = @import("dtype");
const DataType = dtype.DataType;
const DateTime = dtype.DateTime;
const UUID = dtype.UUID;

// TODO: Move this outside of FileEngine and make it faster
// And add some features like
//  - Option to pretty print (add \n and \t)

const ZipponError = @import("error").ZipponError;

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

pub fn writeHeaderCsv(
    writer: anytype,
    members: [][]const u8,
    delimiter: u8,
) !void {
    for (members, 0..) |member, i| {
        try writer.writeAll(member);
        if (i < members.len - 1) try writer.writeByte(delimiter);
    }
    try writer.writeByte('\n');
}

pub fn writeEntityCsv(
    writer: anytype,
    row: []zid.Data,
    data_types: []const DataType,
    delimiter: u8,
) !void {
    for (0..row.len) |i| {
        try writeValue(writer, row[i], data_types[i]);
        if (i < row.len - 1) try writer.writeByte(delimiter);
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
        .Str => |v| {
            if (std.mem.containsAtLeast(u8, v, 1, "\n")) {
                try writer.print("\"\"\"{s}\"\"\"", .{v});
            } else {
                try writer.print("\"{s}\"", .{v});
            }
        },
        .UUID => |v| {
            if (data_type == .self) {
                try writer.print("\"{s}\"", .{UUID.format_bytes(v)});
                return;
            }
            if (!std.meta.eql(v, dtype.Zero.bytes)) {
                try writer.print("{{<|{s}|>}}", .{v});
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

fn writeArray(writer: anytype, data: zid.Data, data_type: DataType) !void {
    try writer.writeByte('[');
    var iter = try zid.ArrayIterator.init(data);
    switch (data) {
        .IntArray => while (iter.next()) |v| try writer.print("{d}, ", .{v.Int}),
        .FloatArray => while (iter.next()) |v| try writer.print("{d}", .{v.Float}),
        .StrArray => while (iter.next()) |v| if (std.mem.containsAtLeast(u8, v.Str, 1, "\n")) {
            try writer.print("\"\"\"{s}\"\"\"", .{v.Str});
        } else {
            try writer.print("\"{s}\"", .{v.Str});
        },
        .UUIDArray => while (iter.next()) |v| try writer.print("{{<|{s}|>}},", .{v.UUID}),
        .BoolArray => while (iter.next()) |v| try writer.print("{any}", .{v.Bool}),
        .UnixArray => while (iter.next()) |v| {
            const datetime = DateTime.initUnix(v.Unix);
            writer.writeByte('"') catch return ZipponError.WriteError;
            switch (data_type) {
                .date => try datetime.format("YYYY/MM/DD", writer),
                .time => try datetime.format("HH:mm:ss.SSSS", writer),
                .datetime => try datetime.format("YYYY/MM/DD-HH:mm:ss.SSSS", writer),
                else => unreachable,
            }
            try writer.writeAll("\", ");
        },
        else => unreachable,
    }
    try writer.writeByte(']');
}

/// Take a string in the JSON format and look for {<|[16]u8|>}, then will look into the map and check if it can find this UUID
/// If it find it, it ill replace the {<|[16]u8|>} will the value
pub fn updateWithRelation(writer: anytype, input: []const u8, map: std.AutoHashMap([16]u8, JsonString)) ZipponError!void {
    var uuid_bytes: [16]u8 = undefined;
    var start: usize = 0;
    while (std.mem.indexOf(u8, input[start..], "{<|")) |pos| {
        const pattern_start = start + pos + 3;
        const pattern_end = pattern_start + 16;

        // Write the text before the pattern
        writer.writeAll(input[start .. pattern_start - 3]) catch return ZipponError.WriteError;

        if (input[pattern_start - 4] == '[') {
            start = try updateArray(writer, input, map, pattern_start - 3);
            continue;
        }

        @memcpy(uuid_bytes[0..], input[pattern_start..pattern_end]);
        if (map.get(uuid_bytes)) |json_string| {
            writer.writeAll(json_string.slice) catch return ZipponError.WriteError;
        } else {
            writer.writeAll(input[pattern_start - 3 .. pattern_end + 3]) catch return ZipponError.WriteError;
        }
        start = pattern_end + 5;
    }

    // Write any remaining text
    writer.writeAll(input[start..]) catch return ZipponError.WriteError;
}

fn updateArray(writer: anytype, input: []const u8, map: std.AutoHashMap([16]u8, JsonString), origin: usize) ZipponError!usize {
    var uuid_bytes: [16]u8 = undefined;
    var start = origin;
    while (input.len > start + 23 and std.mem.eql(u8, input[start .. start + 3], "{<|") and std.mem.eql(u8, input[start + 19 .. start + 23], "|>},")) : (start += 23) {
        @memcpy(uuid_bytes[0..], input[start + 3 .. start + 19]);
        if (map.get(uuid_bytes)) |json_string| {
            writer.writeAll(json_string.slice) catch return ZipponError.WriteError;
        } else {
            writer.writeAll(input[start .. start + 23]) catch return ZipponError.WriteError;
        }
    }
    return start;
}
