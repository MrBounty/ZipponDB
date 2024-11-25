# Data types

There is 8 data types:

- `int`: 32 bit integer
- `float`: 64 bit float. Need to have a dot, `1.` is a float `1` is an integer
- `bool`: Boolean, can be `true` or `false`
- `string`: Character array between `''`
- `UUID`: Id in the UUID format, used for relationship, ect. All struct have an id member
- `date`: A date in yyyy/mm/dd
- `time`: A time in hh:mm:ss.mmmm
- `datetime`: A date time in yyyy/mm/dd-hh:mm:ss:mmmm

All data types can be an array of those types using `[]` in front of it. So `[]int` is an array of integer.

## Date and time

ZipponDB use 3 different date and time data type. Those are use like any other type like `int` or `float`.

### Date

Data type `date` represent a single day. To write a date, you use this format: `yyyy/mm/dd`.
Like that: `2024/10/19`.

### Time

Data type `time` represent a time of the day. To write a time, you use this format: `hh:mm:ss.mmmmm`.
Like that: `12:45:00.0000`.

Millisecond and second are optional so this work too: `12:45:00` and `12:45`

### Datetime

Data type `datetime` mix of both, it use this format: `yyyy/mm/dd-hh:mm:ss.mmmmm`.
Like that: `2024/10/19-12:45:00.0000`.

Millisecond and second are optional so this work too: `2024/10/19-12:45:00` and `2024/10/19-12:45`
