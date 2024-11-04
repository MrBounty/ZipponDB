***Benchmark are set to quicly evolve. I have currently multiple ideas to improve perf***

# Intro

In this example I create a random dataset of 50 000 000 Users using this shema:
```lua
User (
  name: str,
  age: int,
  email: str,
  bday: date,
  last_order: datetime,
  a_time: time,
  scores: []int,
  friends: []str,
)
```

Here a user example:
```
run "ADD User (name = 'Diana Lopez',age = 2,email = 'allisonwilliams@example.org',scores=[37 85 90 71 88 85 68],friends = [],bday=1973/11/13,last_order=1979/07/18-15:05:26.590261,a_time=03:04:06.862213)
```

First let's do a query that parse all file but dont return anything, so we have the time to read and evaluate file but not writting and sending output.
```
run "GRAB User {name = 'asdfqwer'}"
```

## 50 000 000 Users
This take 6.24GB space on disk, seperated into xx files of xx MB

| Thread | Time (s) | Usage (%) |
| --- | --- | --- |
| 1 | 40 | 10 |
| 2 | 21 | 18 |
| 3 | 15 | 25 |
| 4 | 12 | 30 |
| 6 | 8.3 | 45 |
| 8 | 6.6 | 55 |
| 12 | 5.1 | 85 |
| 16 | 4.3 | 100 |

![alt text](https://github.com/MrBounty/ZipponDB/blob/v0.1.4/charts/time_usage_per_thread_50_000_000.png)

## 1 000 000
This take 127MB space on disk, sperated into 24 files of 5.2MB

| Thread | Time (ms) | 
| --- | --- | 
| 1 | 790 | 
| 2 | 446 | 
| 3 | 326 | 
| 4 | 255 | 
| 6 | 195 | 
| 8 | 155 | 
| 12 | 136 | 
| 16 | 116 | 

![alt text](https://github.com/MrBounty/ZipponDB/blob/v0.1.4/charts/time_usage_per_thread_1_000_000.png)

## TODO

- [ ] Benchmark per files size, to find the optimal one. For 10kB, 5MB, 100MB, 1GB
- [ ] Create a build command to benchmark. For 1_000, 1_000_000, 50_000_000 users
    - [ ] Create a random dataset
    - [ ] Do simple query, get average and +- time by set of 25 query
    - [ ] Return the data to do a chart
