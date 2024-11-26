# Data types

ZipponDB have a little set of types. This is on purpose, to keep the database simple and fast. But more type may be added in the future.

## Primary Data Types

ZipponDB supports 8 primary data types:

| Type | Description | Example |
|------|-------------|---------|
| int | 32-bit integer | 42 |
| float | 64-bit float (must include a decimal point) | 3.14 |
| bool | Boolean value | true or false |
| string | Character array enclosed in single quotes | 'Hello, World!' |
| UUID | Universally Unique Identifier | 123e4567-e89b-12d3-a456-426614174000 |
| date | Date in yyyy/mm/dd format | 2024/10/19 |
| time | Time in hh:mm:ss.mmmm format | 12:45:00.0000 |
| datetime | Combined date and time | 2024/10/19-12:45:00.0000 |

## Array Types

Any of these data types can be used as an array by prefixing it with `[]`. For example:

- `[]int`: An array of integers
- `[]string`: An array of strings
