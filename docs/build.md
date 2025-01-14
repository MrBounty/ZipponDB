# Build

On this page, I will show you how to build ZipponDB from source.

## 1. Get Zig

First thing first, <a href="https://ziglang.org/" target="_blank">go get zig</a>.

## 2. Clone repo

Simple enough, clone ZipponDB repository and cd into it.

```bash
git clone https://github.com/MrBounty/ZipponDB
cd ZipponDB
```

## 3. Config

In `lib/config.zig` you will find a config file. There is few parameters and they are comptime for now (can't change from cli). But more will be added.

Parameter | Default | Description
----- | ----- | ---------------
MAX_FILE_SIZE | 1Mb | Max size of each individual file where data is store.
CPU_CORE | 16 | Number of thread the pool will use. (At least 4 recommended for db > 100Mb)

## 4. build

```
zig build
```

Create 2 binaries in `zig-out/bin`:

* **zippondb:** The database CLI.
* **benchmark:** Run and print a benchmark.

### build run

```
zig build run
```

Build and run the CLI.

### build benchmark

```
zig build benchmark
```

Build and run the benchmark.

### build test

```
zig build test
```

Build and run tests.
