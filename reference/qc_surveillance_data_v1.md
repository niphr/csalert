# Check that a surveillance feed has data and is up to date

Checks the input of one indicator for too few rows, a missing reference
column, and a newest period older than `expect_latest`. It returns a
verdict, and the caller decides what to do.

## Usage

``` r
qc_surveillance_data_v1(
  d,
  reference_col = "isoyearweek_reference",
  expect_latest = NULL,
  min_rows = 1L
)
```

## Arguments

- d:

  A data.table with the data of one indicator.

- reference_col:

  The reference-period column.

- expect_latest:

  The newest period that the caller expects, or `NULL` to skip the
  check. The check uses `<`, which orders zero-padded `"YYYY-WW"`
  strings correctly.

- min_rows:

  The fewest rows that pass.

## Value

A list with `ok`, `TRUE` when every check passes, and `reasons`, a
character vector that is empty when `ok` is `TRUE`.

## Details

The checks run in that order and stop at the first failure, so `reasons`
has at most one entry.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
section 9.

Other quality control functions:
[`compare_results()`](https://niphr.github.io/csalert/reference/compare_results.md),
[`qc_week_over_week_v1()`](https://niphr.github.io/csalert/reference/qc_week_over_week_v1.md)

## Examples

``` r
d <- data.table::data.table(
  isoyearweek_reference = c("2023-01", "2023-02"),
  numerator = c(10, 12)
)

qc_surveillance_data_v1(d)
#> $ok
#> [1] TRUE
#> 
#> $reasons
#> character(0)
#> 

# the feed has not been updated as far as the caller expected
qc_surveillance_data_v1(d, expect_latest = "2023-05")
#> $ok
#> [1] FALSE
#> 
#> $reasons
#> [1] "latest reference 2023-02 < expected 2023-05 (feed not updated)"
#> 

# nothing arrived at all
qc_surveillance_data_v1(d[0])
#> $ok
#> [1] FALSE
#> 
#> $reasons
#> [1] "no data (or fewer rows than min_rows)"
#> 
```
