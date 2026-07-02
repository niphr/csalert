# Compare two collapsed csfmt result sets

Compare two collapsed csfmt result sets

## Usage

``` r
compare_results(current, previous)
```

## Arguments

- current, previous:

  data.tables (or csfmt_rts_data_v3) from two runs.

## Value

A long data.table: identity + isoyearweek + column + role/q/level +
\`cur\`/\`prv\`.
