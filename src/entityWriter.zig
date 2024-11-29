const std = @import("std");
const utils = @import("stuffs/utils.zig");
const zid = @import("ZipponData");
const AdditionalData = @import("stuffs/additionalData.zig").AdditionalData;
const dtype = @import("dtype");
const DataType = dtype.DataType;
const DateTime = dtype.DateTime;
const UUID = dtype.UUID;

const ZipponError = @import("stuffs/errors.zig").ZipponError;

pub const EntityWriter = struct {
    pub fn writeEntityTable(
        writer: anytype,
        row: []zid.Data,
        additional_data: *AdditionalData,
        data_types: []const DataType,
    ) !void {
        try writer.writeAll("| ");
        for (additional_data.member_to_find.items) |member| {
            try writeValue(writer, row[member.index], data_types[member.index]);
            try writer.writeAll(" \t| ");
        }
        try writer.writeByte('\n');
    }

    pub fn writeEntityJSON(
        writer: anytype,
        row: []zid.Data,
        additional_data: *AdditionalData,
        data_types: []const DataType,
    ) !void {
        try writer.writeByte('{');
        for (additional_data.member_to_find.items) |member| {
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
                const uuid = try UUID.parse("00000000-0000-0000-0000-000000000000"); // Maybe pass that comptime to prevent parsing it everytime
                if (!std.meta.eql(v, uuid.bytes)) {
                    try writer.print("\"{s}\"", .{UUID.format_bytes(v)});
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
            .UUIDArray => while (iter.next()) |v| writer.print("\"{s}\"", .{UUID.format_bytes(v.UUID)}) catch return ZipponError.WriteError,
            .BoolArray => while (iter.next()) |v| writer.print("{any}", .{v.Bool}) catch return ZipponError.WriteError,
            .UnixArray => {
                while (iter.next()) |v| {
                    const datetime = DateTime.initUnix(v.Unix);
                    writer.writeByte('"') catch return ZipponError.WriteError;
                    switch (data_type) {
                        .date => datetime.format("YYYY/MM/DD", writer) catch return ZipponError.WriteError,
                        .time => datetime.format("HH:mm:ss.SSSS", writer) catch return ZipponError.WriteError,
                        .datetime => datetime.format("YYYY/MM/DD-HH:mm:ss.SSSS", writer) catch return ZipponError.WriteError,
                        else => unreachable,
                    }
                    writer.writeAll("\", ") catch return ZipponError.WriteError;
                }
            },
            else => unreachable,
        }
        writer.writeByte(']') catch return ZipponError.WriteError;
    }
};
