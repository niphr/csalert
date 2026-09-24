# Turn a reporting triangle into one count matrix per series

Returns, for each series, a matrix of counts with one row per reference
week and one column per delay day. Every nowcast engine calls it first.

## Usage

``` r
reporting_triangle_matrix(
  triangle,
  max_delay_days,
  value_col = attr(triangle, "value_col")
)
```

## Arguments

- triangle:

  The `csfmt_reporting_triangle_v3` to turn into matrices.

- max_delay_days:

  The number of delay columns, in days. With 35, the columns are delay
  days 0 to 34, and a report at delay 35 or 400 counts in column `"34"`.

- value_col:

  The count column. The default is the `value_col` of the triangle. Give
  a denominator column to get its matrix.

## Value

A list named by `time_series_id`. Each element holds `reference`, the
ISO weeks of the rows, and `mat`, the matrix. A cell sums its counts
with `na.rm = TRUE`, so a cell with only `NA` counts is 0.

## Details

The rows run over every ISO week from the first to the last reference
week. A week with no report is a row of zeros. The last column also
holds every later delay, so a late report adds to `rowSums(mat)`. A
report before its reference Monday has a negative delay, and is dropped.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
stage 3, which reads the delay distribution from these counts.

Other reporting triangle functions:
[`csfmt_reporting_triangle_v3()`](https://niphr.github.io/csalert/reference/csfmt_reporting_triangle_v3.md),
[`isoyearweek_week_start()`](https://niphr.github.io/csalert/reference/isoyearweek_week_start.md)

## Examples

``` r
cal <- cstime::dates_by_isoyearweek
i <- match("2023-01", cal$isoyearweek)
set.seed(1)
monday <- as.Date(cal$mon[i + rep(0:39, each = 3)])
d <- data.table::data.table(
  isoyearweek_reference = cal$isoyearweek[i + rep(0:39, each = 3)],
  reporting_date = monday + rep(c(3, 10, 17), 40),
  numerator = rpois(120, c(30, 15, 5)),
  indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
)
d <- d[reporting_date <= as.Date(cal$mon[i + 39]) + 6]
tri <- csfmt_reporting_triangle_v3(
  d,
  id_cols = c("indicator_tag", "location_code", "age", "sex")
)

m <- reporting_triangle_matrix(tri, max_delay_days = 21)
names(m)
#> [1] "d8da72e3fbb5fd29"

# rows are reference weeks, columns are delay days 0 to 20
dim(m[[1]]$mat)
#> [1] 40 21
head(m[[1]]$reference, 3)
#> [1] "2023-01" "2023-02" "2023-03"

# this series reports on days 3, 10 and 17 after the reference Monday
m[[1]]$mat[1:3, c("3", "10", "17")]
#>       3 10 17
#> [1,] 26 20  8
#> [2,] 38 16  3
#> [3,] 24 17  6

# the newest weeks are only partly reported: the later delays are still zero
tail(m[[1]]$mat[, c("3", "10", "17")], 3)
#>        3 10 17
#> [38,] 27 21  3
#> [39,] 24 20  0
#> [40,] 20  0  0
```
