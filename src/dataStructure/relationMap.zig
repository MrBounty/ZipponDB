// A relation map is all data needed to add relationship at the during parsing
// How it work is that, the first time I parse the struct files, like User, I populate a map of UUID empty string
// And in the JSON string I write {<|[16]u8|>} inside. Then I can use this struct to parse the file again
// And if the UUID is in the map, I write the JSON if in its value in the map
// It need to be recurcive as additional data can do stuff like [name, friends [name, best_friend]]
// I could use parseEntities in a recursive way. But that mean ready the file at each loop =/
//
// No no no, But on the other hands that would solve the issue of getting the UUID of the best_friend
// Fuck thats true, I didnt think about that. I can one populate the UUID that I want from the current depth of the additional data
// So I need to parse multiple time. But that sove when using with multiple parse.
// Because GRAB User [comments [post]]. How do I get the UUID of the Post if I only parse User ?
//
// Ok so I need to go recursive on parseEntities
// So I parse one time, if additional data has relationship, I create a list of RelationMap
// When I parse, I populate RelationMap with UUID I want
// Then for each RelationMap, I parse the files again this time to update the first JSON that now have {<||>}
// With a sub additionalData. If there is an additional data relation, I recurcive.
// So I need an option in parseEntity to either write the first JSON or update the existing one

const std = @import("std");
const AdditionalData = @import("additionalData.zig").AdditionalData;
const ZipponError = @import("error").ZipponError;

pub const JsonString = struct {
    slice: []const u8 = "",
    init: bool = false,
};

pub const RelationMap = @This();
struct_name: []const u8,
member_name: []const u8,
additional_data: AdditionalData,
map: *std.AutoHashMap([16]u8, JsonString),

/// Will use a string in the JSON format and look for {<|[16]u8|>}
/// It will then check if it is for the right member name and if so, add an empty JSON string at the key
pub fn populate(self: *RelationMap, input: []const u8) ZipponError!void {
    var uuid_bytes: [16]u8 = undefined;
    var start: usize = 0;
    while (std.mem.indexOf(u8, input[start..], "{<|")) |pos| {
        const pattern_start = start + pos + 3;
        const pattern_end = pattern_start + 16;
        defer start = pattern_end + 3;

        const member_end = if (input[pattern_start - 4] == '[') pattern_start - 6 else pattern_start - 5; // This should be ": {<|"
        var member_start = member_end - 1;
        while (input[member_start] != ' ' and input[member_start] != '[' and input[member_start] != '{') : (member_start -= 1) {}
        member_start += 1;

        if (!std.mem.eql(u8, input[member_start..member_end], self.member_name)) continue;

        if (input[pattern_start - 4] == '[') {
            start = try self.populateArray(input, pattern_start - 3);
            continue;
        }

        @memcpy(uuid_bytes[0..], input[pattern_start..pattern_end]);

        self.map.put(uuid_bytes, JsonString{}) catch return ZipponError.MemoryError;
    }
}

// Array are pack in format {<|[16]u8|>},{<|[16]u8|>},{<|[16]u8|>},{<|[16]u8|>},
fn populateArray(self: *RelationMap, input: []const u8, origin: usize) ZipponError!usize {
    var uuid_bytes: [16]u8 = undefined;
    var start = origin;
    while (input.len > start + 23 and std.mem.eql(u8, input[start .. start + 3], "{<|") and std.mem.eql(u8, input[start + 19 .. start + 23], "|>},")) : (start += 23) {
        for (start + 3..start + 19, 0..) |i, j| uuid_bytes[j] = input[i];
        self.map.put(uuid_bytes, JsonString{}) catch return ZipponError.MemoryError;
    }
    return start;
}
