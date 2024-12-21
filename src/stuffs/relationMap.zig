// A relation map is all data needed to add relationship at the during parsing
// How it work is that, the first time I parse the struct files, like User, I populate a map of UUID empty string
// And in the JSON string I write {|<[16]u8>|} inside. Then I can use this struct to parse the file again
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
// Then for each RelationMap, I parse the files again this time to update the first JSON that now have {|<>|}
// With a sub additionalData. If there is an additional data relation, I recurcive.
// So I need an option in parseEntity to either write the first JSON or update the existing one

const std = @import("std");
const AdditionalData = @import("stuffs/additionalData.zig").AdditionalData;

pub const JsonString = struct {
    slice: []const u8 = "",
    init: bool = false,
};

pub const RelationMap = struct {
    struct_name: []const u8,
    additional_data: AdditionalData,
    map: *std.AutoHashMap([16]u8, JsonString),
};
