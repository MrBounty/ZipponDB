// This file is just to expose what I need to grab

pub const UUID = @import("uuid.zig").UUID;
pub const DateTime = @import("date.zig").DateTime;
pub const OR = @import("uuid.zig").OR;
pub const AND = @import("uuid.zig").AND;
pub const s2t = @import("stringToType.zig");

/// Suported dataType for the DB
/// Maybe start using a unionenum
pub const DataType = enum {
    int,
    float,
    str,
    bool,
    link,
    self, // self represent itself, it is the id
    date,
    time,
    datetime,
    int_array,
    float_array,
    str_array,
    bool_array,
    date_array,
    time_array,
    datetime_array,
    link_array,

    pub fn is_array(self: DataType) bool {
        return switch (self) {
            .int_array, .float_array, .str_array, .bool_array, .date_array, .time_array, .datetime_array, .link_array => true,
            else => false,
        };
    }
};
