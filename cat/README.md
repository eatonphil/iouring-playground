To run:

```
$ zig build-exe main.zig
$ ./main
$ duckdb -c "select column0 as method, avg(cast(column1 as double)) || 's' avg_time, format_bytes(avg(column2::double)::bigint) || '/s' as throughput from 'out.csv' group by column0 order by avg(cast(column1 as double)) asc"
```

And observe:

```
┌─────────┬─────────────────────┬────────────┐
│ method  │      avg_time       │ throughput │
│ varchar │       varchar       │  varchar   │
├─────────┼─────────────────────┼────────────┤
│ iouring │ 1.3281296271999998s │ 308.4MB/s  │
│ read    │ 1.3604438662s       │ 301.0MB/s  │
└─────────┴─────────────────────┴────────────┘
```
