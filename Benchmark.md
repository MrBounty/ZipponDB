***Benchmark a set to quicly evolve***

# Config

# 50 000 000 users

In this example I create a random dataset of 50 000 000 Users using this shema:
```
TODO
```

Here a user example:
```
run "ADD User (name = 'Diana Lopez',age = 2,email = 'allisonwilliams@example.org',scores=[37 85 90 71 88 85 68],friends = [],bday=1973/11/13,last_order=1979/07/18-15:05:26.590261,a_time=03:04:06.862213)
```

### Space on disk

This take 6.24GB

### Parse all data

First let's do a query that parse all file but dont return anything, so we have the time to read and evaluate file but not writting and sending output.
```
run "GRAB User {name = 'asdfqwer'}
```

#### Time per jobs

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

![alt text](https://github.com/MrBounty/ZipponDB/blob/main/charts/time_usage_per_thread.png)

