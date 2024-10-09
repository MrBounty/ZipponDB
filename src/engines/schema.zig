// This file is named and use as a struct but is in fact just a series of utils functions to get and check the schema
// TODO: create a struct like SchemaEngine so I can do propre testing and it make update it easier
// Also can put the migration stuff in here

const std = @import("std");
const DataType = @import("types/dataType.zig").DataType;

pub const struct_name_list: [2][]const u8 = .{
    "User",
    "Message",
};

pub const struct_member_list: [2][]const []const u8 = .{
    &[_][]const u8{ "name", "email", "age", "scores", "friends" },
    &[_][]const u8{"content"},
};

pub const struct_type_list: [2][]const DataType = .{
    &[_]DataType{ .str, .str, .int, .int_array, .bool_array },
    &[_]DataType{.str},
};

// use to know how much token the Parser of the FileEngine need to pass before the right one
pub fn columnIndexOfMember(struct_name: []const u8, member_name: []const u8) ?usize {
    var i: u16 = 0;

    for (structName2structMembers(struct_name)) |mn| {
        if (std.mem.eql(u8, mn, member_name)) return i;
        i += 1;
    }

    return null;
}

/// Get the type of the member
pub fn memberName2DataType(struct_name: []const u8, member_name: []const u8) ?DataType {
    var i: u16 = 0;

    for (structName2structMembers(struct_name)) |mn| {
        if (std.mem.eql(u8, mn, member_name)) return structName2DataType(struct_name)[i];
        i += 1;
    }

    return null;
}

/// Get the list of all member name for a struct name
pub fn structName2structMembers(struct_name: []const u8) []const []const u8 {
    var i: u16 = 0;

    while (i < struct_name_list.len) : (i += 1) if (std.mem.eql(u8, struct_name_list[i], struct_name)) break;

    if (i == struct_name_list.len) {
        std.debug.print("{s} \n", .{struct_name});
        @panic("Struct name not found!");
    }

    return struct_member_list[i];
}

pub fn structName2DataType(struct_name: []const u8) []const DataType {
    var i: u16 = 0;

    while (i < struct_name_list.len) : (i += 1) if (std.mem.eql(u8, struct_name_list[i], struct_name)) break;

    return struct_type_list[i];
}

/// Chech if the name of a struct is in the current schema
pub fn isStructNameExists(struct_name: []const u8) bool {
    for (struct_name_list) |sn| if (std.mem.eql(u8, sn, struct_name)) return true;
    return false;
}

/// Check if a struct have the member name
pub fn isMemberNameInStruct(struct_name: []const u8, member_name: []const u8) bool {
    for (structName2structMembers(struct_name)) |mn| if (std.mem.eql(u8, mn, member_name)) return true;
    return false;
}

/// Take a struct name and a member name and return true if the member name is part of the struct
pub fn isMemberPartOfStruct(struct_name: []const u8, member_name: []const u8) bool {
    const all_struct_member = structName2structMembers(struct_name);

    for (all_struct_member) |key| {
        if (std.mem.eql(u8, key, member_name)) return true;
    }

    return false;
}

/// Check if a string is a name of a struct in the currently use engine
pub fn isStructInSchema(struct_name_to_check: []const u8) bool {
    for (struct_name_list) |struct_name| {
        if (std.mem.eql(u8, struct_name_to_check, struct_name)) {
            return true;
        }
    }
    return false;
}

// Return true if the map have all the member name as key and not more
pub fn checkIfAllMemberInMap(struct_name: []const u8, map: *std.StringHashMap([]const u8)) bool {
    const all_struct_member = structName2structMembers(struct_name);
    var count: u16 = 0;

    for (all_struct_member) |key| {
        if (map.contains(key)) count += 1 else std.debug.print("Missing: {s}\n", .{key});
    }

    return ((count == all_struct_member.len) and (count == map.count()));
}
