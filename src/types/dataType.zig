/// Suported dataType for the DB
/// Maybe start using a unionenum
pub const DataType = enum {
    int,
    float,
    str,
    bool,
    link,
    date,
    time,
    datetime,
    int_array,
    float_array,
    str_array,
    bool_array,
    link_array,
    date_array,
    time_array,
    datetime_array,
};
