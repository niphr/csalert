# Quality-control checks on surveillance input data

Quality-control checks on surveillance input data

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

  A data.table of one indicator's data.

- reference_col:

  The reference time column (default "isoyearweek_reference").

- expect_latest:

  Optional: the latest reference period that \*should\* be present. If
  \`max(reference) \< expect_latest\`, the feed is flagged stale.

- min_rows:

  Minimum rows required (default 1).

## Value

A list: \`ok\` (logical) and \`reasons\` (character vector; empty if
ok).

## See also

Neither package vignette covers input quality control. This function
returns a verdict and nothing else – the caller decides what to do with
it.
[`qc_week_over_week_v1`](https://niphr.github.io/csalert/reference/qc_week_over_week_v1.md)
answers a different question, about two finished runs rather than one
input feed.

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
