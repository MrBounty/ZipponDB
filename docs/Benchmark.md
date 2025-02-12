# Benchmark

***Benchmark are set to evolve. I have currently multiple ideas to improve performance.***

ZipponDB is fairly fast and can easely query millions of entities. 
Current limitation is around 5GB I would say, depending of CPU cores, usage and kind of data saved.
After that query can start to become slow as optimizations are still missing.

Most of query's time is writing entities into a JSON format. Parsing the file itself take little time.
For example in the benchmark report bellow, I parse 100 000 users in around 40ms if there is no entities to send and 130ms if all 100 000 entities are to send.

I choosed to release ZipponDB binary with the small release. 
Zig has a fast and safe release, but the fast release isn't that much faster in my case, if not at all.
If you want you can build it with it.

## Command

You can run `zig build benchmark`, if you clone the repo to benchmark your machine.
[More info on how to build from source.](/ZipponDB/build)

Here an example on my machine with 16 core:

```
=====================================

Populating with 5000 users.
Populate duration: 0.035698 seconds

Database path: benchmarkDB
Total size: 0.36Mb
CPU core: 16
Max file size: 5.00Mb
LOG: 0.02Mb
BACKUP: 0.00Mb
DATA: 0.33Mb
  Item: 0.00Mb | 19 entities | 1 files
  User: 0.33Mb | 5000 entities | 1 files
  Order: 0.00Mb | 0 entities | 1 files
  Category: 0.00Mb | 4 entities | 1 files

--------------------------------------

Query:  GRAB User {}
Time:    16.90 ± 25.22 ms | Min     8.25ms | Max    92.55ms

Query:  GRAB User {name='asd'}
Time:     2.62 ± 0.10  ms | Min     2.52ms | Max     2.85ms

Query:  GRAB User [1] {}
Time:     0.16 ± 0.01  ms | Min     0.15ms | Max     0.18ms

Query:  GRAB User [name] {}
Time:     7.88 ± 11.69 ms | Min     3.91ms | Max    42.94ms

Query:  GRAB User {name = 'Charlie'}
Time:     3.87 ± 0.16  ms | Min     3.70ms | Max     4.17ms

Query:  GRAB Category {}
Time:     0.20 ± 0.07  ms | Min     0.17ms | Max     0.41ms

Query:  GRAB Item {}
Time:     0.21 ± 0.02  ms | Min     0.19ms | Max     0.25ms

Query:  GRAB Order {}
Time:     0.14 ± 0.01  ms | Min     0.13ms | Max     0.18ms

Query:  GRAB Order [from, items, quantity, at] {}
Time:     4.18 ± 12.01 ms | Min     0.15ms | Max    40.21ms

Query:  DELETE User {}
Time:     0.64 ± 1.13  ms | Min     0.23ms | Max     4.04ms

Read:   1907698 Entity/second   *Include small condition
Write:  350200 Entity/second

=====================================

Populating with 100000 users.
Populate duration: 0.707605 seconds

Database path: benchmarkDB
Total size: 6.62Mb
CPU core: 16
Max file size: 5.00Mb
LOG: 0.02Mb
BACKUP: 0.00Mb
DATA: 6.59Mb
  Item: 0.00Mb | 19 entities | 1 files
  User: 6.59Mb | 100000 entities | 2 files
  Order: 0.00Mb | 0 entities | 1 files
  Category: 0.00Mb | 4 entities | 1 files

--------------------------------------

Query:  GRAB User {}
Time:   126.99 ± 3.05  ms | Min   123.37ms | Max   133.56ms

Query:  GRAB User {name='asd'}
Time:    38.12 ± 1.60  ms | Min    36.48ms | Max    41.88ms

Query:  GRAB User [1] {}
Time:     0.19 ± 0.02  ms | Min     0.16ms | Max     0.22ms

Query:  GRAB User [name] {}
Time:    59.33 ± 1.29  ms | Min    58.02ms | Max    61.47ms

Query:  GRAB User {name = 'Charlie'}
Time:    53.29 ± 1.00  ms | Min    51.50ms | Max    54.78ms

Query:  GRAB Category {}
Time:     0.19 ± 0.01  ms | Min     0.18ms | Max     0.22ms

Query:  GRAB Item {}
Time:     5.51 ± 13.43 ms | Min     0.22ms | Max    45.22ms

Query:  GRAB Order {}
Time:     0.16 ± 0.01  ms | Min     0.15ms | Max     0.18ms

Query:  GRAB Order [from, items, quantity, at] {}
Time:     0.17 ± 0.02  ms | Min     0.15ms | Max     0.21ms

Query:  DELETE User {}
Time:     5.96 ± 17.04 ms | Min     0.26ms | Max    57.07ms

Read:   2623338 Entity/second   *Include small condition
Write:  1125278 Entity/second

=====================================

Populating with 1000000 users.
Populate duration: 7.029142 seconds

Database path: benchmarkDB
Total size: 65.96Mb
CPU core: 16
Max file size: 5.00Mb
LOG: 0.02Mb
BACKUP: 0.00Mb
DATA: 65.93Mb
  Item: 0.00Mb | 19 entities | 1 files
  User: 65.93Mb | 1000000 entities | 14 files
  Order: 0.00Mb | 0 entities | 1 files
  Category: 0.00Mb | 4 entities | 1 files

--------------------------------------

Query:  GRAB User {}
Time:   250.77 ± 6.74  ms | Min   247.08ms | Max   270.61ms

Query:  GRAB User {name='asd'}
Time:    67.90 ± 0.42  ms | Min    67.31ms | Max    68.78ms

Query:  GRAB User [1] {}
Time:     8.92 ± 24.86 ms | Min     0.55ms | Max    83.51ms

Query:  GRAB User [name] {}
Time:   110.08 ± 5.27  ms | Min   106.86ms | Max   125.21ms

Query:  GRAB User {name = 'Charlie'}
Time:    73.65 ± 2.79  ms | Min    69.24ms | Max    79.22ms

Query:  GRAB Category {}
Time:     0.19 ± 0.04  ms | Min     0.16ms | Max     0.33ms

Query:  GRAB Item {}
Time:     0.21 ± 0.02  ms | Min     0.19ms | Max     0.26ms

Query:  GRAB Order {}
Time:     0.15 ± 0.01  ms | Min     0.14ms | Max     0.17ms

Query:  GRAB Order [from, items, quantity, at] {}
Time:     0.17 ± 0.01  ms | Min     0.16ms | Max     0.18ms

Query:  DELETE User {}
Time:    11.74 ± 34.19 ms | Min     0.29ms | Max   114.30ms

Read:   14727354 Entity/second  *Include small condition
Write:  5468517 Entity/second

=====================================

Populating with 10000000 users.
Populate duration: 72.675680 seconds

Database path: benchmarkDB
Total size: 659.33Mb
CPU core: 16
Max file size: 5.00Mb
LOG: 0.02Mb
BACKUP: 0.00Mb
DATA: 659.30Mb
  Item: 0.00Mb | 19 entities | 1 files
  User: 659.30Mb | 10000000 entities | 132 files
  Order: 0.00Mb | 0 entities | 1 files
  Category: 0.00Mb | 4 entities | 1 files

--------------------------------------

Query:  GRAB User {}
Time:   2535.29 ± 86.92 ms | Min  2448.39ms | Max  2712.78ms

Query:  GRAB User {name='asd'}
Time:   684.75 ± 39.96 ms | Min   649.09ms | Max   797.13ms

Query:  GRAB User [1] {}
Time:     6.65 ± 1.00  ms | Min     5.36ms | Max     8.75ms

Query:  GRAB User [name] {}
Time:   1106.21 ± 33.57 ms | Min  1056.57ms | Max  1172.61ms

Query:  GRAB User {name = 'Charlie'}
Time:   690.56 ± 20.41 ms | Min   661.51ms | Max   718.07ms

Query:  GRAB Category {}
Time:     0.21 ± 0.03  ms | Min     0.18ms | Max     0.31ms

Query:  GRAB Item {}
Time:     0.23 ± 0.04  ms | Min     0.19ms | Max     0.32ms

Query:  GRAB Order {}
Time:     0.15 ± 0.01  ms | Min     0.13ms | Max     0.17ms

Query:  GRAB Order [from, items, quantity, at] {}
Time:     0.17 ± 0.02  ms | Min     0.15ms | Max     0.21ms

Query:  DELETE User {}
Time:   109.55 ± 326.64ms | Min     0.47ms | Max  1089.46ms

Read:   14603810 Entity/second  *Include small condition
Write:  5403847 Entity/second
=====================================
```

