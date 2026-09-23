# Densify a reporting triangle into per-series reference x delay count matrices

Densify a reporting triangle into per-series reference x delay count
matrices

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

  A \`csfmt_reporting_triangle_v3\`.

- max_delay_days:

  Number of delay columns, in DAYS: delay 0 to \`max_delay_days - 1\`.
  \`max_delay_days = 35\` gives delay days 0 to 34, the 35 days that
  start on the reference week's Monday. The last column holds delay
  \`max_delay_days - 1\` AND every later delay, so a report at delay 35
  or 400 counts in column \`"34"\`. A report before the reference Monday
  has a negative delay and is dropped.

- value_col:

  Which value column to reshape (default the triangle's \`value_col\`;
  pass a denominator column to reshape that instead).

## Value

Named list (by time_series_id) of \`list(reference, mat)\`, where
\`mat\` is a reference-week x delay-day count matrix (zeros filled
within the observed region). The rows stay ISO weeks; only the columns
are days. The last column, \`max_delay_days - 1\`, also holds every
report at a later delay. So a late report adds to \`rowSums(mat)\` and
is not lost.

## See also

Neither package vignette covers this function. It is the densification
step every nowcast engine runs first. Reach for it directly only when
you want the raw reference x delay matrix rather than an ensemble.

Other reporting triangle functions:
[`csfmt_reporting_triangle_v3()`](https://niphr.github.io/csalert/reference/csfmt_reporting_triangle_v3.md)

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
