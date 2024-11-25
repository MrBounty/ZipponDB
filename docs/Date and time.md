# Date and time

ZipponDB use 3 different date and time data type. Those are use like any other tpye like `int` or `float`.

## Date

Data type `date` represent a single day. To write a date, you use this format: `yyyy/mm/dd`.
Like that: `2024/10/19`.

## Time

Data type `time` represent a time of the day. To write a time, you use this format: `hh:mm:ss.mmmmm`.
Like that: `12:45:00.0000`.

Millisecond and second are optional so this work too: `12:45:00` and `12:45`

## Datetime

Data type `datetime` mix of both, it use this format: `yyyy/mm/dd-hh:mm:ss.mmmmm`.
Like that: `2024/10/19-12:45:00.0000`.

Millisecond and second are optional so this work too: `2024/10/19-12:45:00` and `2024/10/19-12:45`
