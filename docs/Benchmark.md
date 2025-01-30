# Benchmark

***Benchmark are set to evolve. I have currently multiple ideas to improve performance.***

ZipponDB is fairly fast and can easely query millions of entities. 
Current limitation is around 5GB I would say, depending of the use and kind of data saved.
After that query can start to become slow as multiple optimization are still missing.

Most of query's time is writing entities into a JSON string. Parsing the file itself take little time.
For example in the benchmark report bellow, I parse 100 000 users in around 40ms if there is no entities to send and 130ms if all 100 000 entities are to send.

I choosed to release ZipponDB binary with the small release. Zig has a fast and safe release, but the fast release isn't that much faster, if not at all.

## Command

You can run `zig build benchmark`, if you clone the repo to benchmark your machine. [More info.](/ZipponDB/build)

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

## Other core count

Here some benchmark with different number of cpu core.

Note that don't show 5000 users because it use a single file so there is no multi threading as it is done one thread per file.

### 1

```
=====================================

Populating with 100000 users.
Populate duration: 0.697690 seconds

Database path: benchmarkDB
Total size: 6.62Mb
CPU core: 1
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
Time:   169.31 ± 5.39  ms | Min   163.25ms | Max   181.23ms

Query:  GRAB User {name='asd'}
Time:    49.66 ± 1.14  ms | Min    48.23ms | Max    51.71ms

Query:  GRAB User [1] {}
Time:     0.20 ± 0.02  ms | Min     0.18ms | Max     0.25ms

Query:  GRAB User [name] {}
Time:    75.81 ± 1.01  ms | Min    74.15ms | Max    77.42ms

Query:  GRAB User {name = 'Charlie'}
Time:    73.54 ± 1.00  ms | Min    72.04ms | Max    75.61ms

Query:  GRAB Category {}
Time:     0.16 ± 0.01  ms | Min     0.15ms | Max     0.19ms

Query:  GRAB Item {}
Time:     6.37 ± 18.54 ms | Min     0.18ms | Max    62.01ms

Query:  GRAB Order {}
Time:     0.15 ± 0.01  ms | Min     0.13ms | Max     0.18ms

Query:  GRAB Order [from, items, quantity, at] {}
Time:     0.16 ± 0.02  ms | Min     0.14ms | Max     0.19ms

Query:  DELETE User {}
Time:     8.07 ± 23.43 ms | Min     0.22ms | Max    78.35ms

Read:   2013655 Entity/second   *Include small condition
Write:  835770 Entity/second

=====================================

Populating with 1000000 users.
Populate duration: 7.031715 seconds

Database path: benchmarkDB
Total size: 65.96Mb
CPU core: 1
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
Time:   1720.31 ± 31.89 ms | Min  1674.61ms | Max  1787.15ms

Query:  GRAB User {name='asd'}
Time:   511.09 ± 5.51  ms | Min   501.73ms | Max   521.17ms

Query:  GRAB User [1] {}
Time:     4.34 ± 10.89 ms | Min     0.66ms | Max    37.02ms

Query:  GRAB User [name] {}
Time:   788.89 ± 6.62  ms | Min   779.85ms | Max   802.79ms

Query:  GRAB User {name = 'Charlie'}
Time:   763.96 ± 5.05  ms | Min   752.04ms | Max   771.09ms

Query:  GRAB Category {}
Time:     0.19 ± 0.04  ms | Min     0.15ms | Max     0.28ms

Query:  GRAB Item {}
Time:     0.21 ± 0.02  ms | Min     0.19ms | Max     0.24ms

Query:  GRAB Order {}
Time:     0.13 ± 0.01  ms | Min     0.12ms | Max     0.14ms

Query:  GRAB Order [from, items, quantity, at] {}
Time:     0.16 ± 0.01  ms | Min     0.15ms | Max     0.19ms

Query:  DELETE User {}
Time:    78.98 ± 236.07ms | Min     0.24ms | Max   787.18ms

Read:   1956584 Entity/second   *Include small condition
Write:  826982 Entity/second

=====================================

Populating with 10000000 users.
Populate duration: 74.074046 seconds

Database path: benchmarkDB
Total size: 659.33Mb
CPU core: 1
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
Time:   18117.45 ± 106.80ms | Min 17946.04ms | Max 18349.54ms

Query:  GRAB User {name='asd'}
Time:   5141.26 ± 67.78 ms | Min  5059.89ms | Max  5275.02ms

Query:  GRAB User [1] {}
Time:     5.71 ± 0.22  ms | Min     5.34ms | Max     6.27ms

Query:  GRAB User [name] {}
Time:   7863.72 ± 26.90 ms | Min  7823.04ms | Max  7911.72ms

Query:  GRAB User {name = 'Charlie'}
Time:   7724.32 ± 38.54 ms | Min  7671.13ms | Max  7812.13ms

Query:  GRAB Category {}
Time:     0.21 ± 0.07  ms | Min     0.15ms | Max     0.38ms

Query:  GRAB Item {}
Time:     0.22 ± 0.07  ms | Min     0.18ms | Max     0.42ms

Query:  GRAB Order {}
Time:     0.14 ± 0.01  ms | Min     0.13ms | Max     0.17ms

Query:  GRAB Order [from, items, quantity, at] {}
Time:     0.17 ± 0.03  ms | Min     0.14ms | Max     0.25ms

Query:  DELETE User {}
Time:   796.37 ± 2387.51ms | Min     0.41ms | Max  7958.91ms

Read:   1945047 Entity/second   *Include small condition
Write:  770643 Entity/second
=====================================
```

### 4

```
=====================================

Populating with 100000 users.
Populate duration: 0.700273 seconds

Database path: benchmarkDB
Total size: 6.62Mb
CPU core: 4
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
Time:   131.92 ± 1.79  ms | Min   129.06ms | Max   135.24ms

Query:  GRAB User {name='asd'}
Time:    38.23 ± 1.12  ms | Min    36.52ms | Max    40.35ms

Query:  GRAB User [1] {}
Time:     0.17 ± 0.02  ms | Min     0.15ms | Max     0.22ms

Query:  GRAB User [name] {}
Time:    60.60 ± 1.52  ms | Min    58.62ms | Max    64.49ms

Query:  GRAB User {name = 'Charlie'}
Time:    53.90 ± 1.46  ms | Min    52.44ms | Max    56.96ms

Query:  GRAB Category {}
Time:     0.17 ± 0.02  ms | Min     0.15ms | Max     0.21ms

Query:  GRAB Item {}
Time:     3.70 ± 10.47 ms | Min     0.19ms | Max    35.10ms

Query:  GRAB Order {}
Time:     0.13 ± 0.00  ms | Min     0.13ms | Max     0.14ms

Query:  GRAB Order [from, items, quantity, at] {}
Time:     0.18 ± 0.07  ms | Min     0.15ms | Max     0.39ms

Query:  DELETE User {}
Time:     6.00 ± 17.36 ms | Min     0.21ms | Max    58.08ms

Read:   2615841 Entity/second   *Include small condition
Write:  1067359 Entity/second

=====================================

Populating with 1000000 users.
Populate duration: 6.912029 seconds

Database path: benchmarkDB
Total size: 65.96Mb
CPU core: 4
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
Time:   580.46 ± 7.08  ms | Min   566.39ms | Max   591.97ms

Query:  GRAB User {name='asd'}
Time:   166.33 ± 3.12  ms | Min   161.76ms | Max   171.96ms

Query:  GRAB User [1] {}
Time:     2.88 ± 6.81  ms | Min     0.53ms | Max    23.32ms

Query:  GRAB User [name] {}
Time:   262.20 ± 5.78  ms | Min   255.59ms | Max   273.91ms

Query:  GRAB User {name = 'Charlie'}
Time:   190.25 ± 5.76  ms | Min   184.78ms | Max   204.83ms

Query:  GRAB Category {}
Time:     0.18 ± 0.04  ms | Min     0.16ms | Max     0.29ms

Query:  GRAB Item {}
Time:     0.22 ± 0.02  ms | Min     0.19ms | Max     0.28ms

Query:  GRAB Order {}
Time:     0.14 ± 0.01  ms | Min     0.13ms | Max     0.17ms

Query:  GRAB Order [from, items, quantity, at] {}
Time:     0.16 ± 0.01  ms | Min     0.15ms | Max     0.19ms

Query:  DELETE User {}
Time:    26.91 ± 79.86 ms | Min     0.26ms | Max   266.51ms

Read:   6012012 Entity/second   *Include small condition
Write:  2414729 Entity/second

=====================================

Populating with 10000000 users.
Populate duration: 69.969231 seconds

Database path: benchmarkDB
Total size: 659.33Mb
CPU core: 4
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
Time:   5306.69 ± 34.07 ms | Min  5226.70ms | Max  5344.36ms

Query:  GRAB User {name='asd'}
Time:   1475.91 ± 24.85 ms | Min  1430.52ms | Max  1509.27ms

Query:  GRAB User [1] {}
Time:     4.73 ± 0.30  ms | Min     4.42ms | Max     5.32ms

Query:  GRAB User [name] {}
Time:   2374.83 ± 21.66 ms | Min  2343.64ms | Max  2410.61ms

Query:  GRAB User {name = 'Charlie'}
Time:   1556.61 ± 31.91 ms | Min  1512.58ms | Max  1622.71ms

Query:  GRAB Category {}
Time:     0.21 ± 0.06  ms | Min     0.16ms | Max     0.37ms

Query:  GRAB Item {}
Time:     0.20 ± 0.01  ms | Min     0.19ms | Max     0.24ms

Query:  GRAB Order {}
Time:     0.14 ± 0.01  ms | Min     0.13ms | Max     0.17ms

Query:  GRAB Order [from, items, quantity, at] {}
Time:     0.19 ± 0.05  ms | Min     0.14ms | Max     0.34ms

Query:  DELETE User {}
Time:   246.23 ± 737.02ms | Min     0.43ms | Max  2457.29ms

Read:   6775468 Entity/second   *Include small condition
Write:  2610439 Entity/second
=====================================
```
