# Densify a reporting triangle into per-series reference x delay count matrices

Densify a reporting triangle into per-series reference x delay count
matrices

## Usage

``` r
reporting_triangle_matrix(
  triangle,
  max_delay,
  value_col = attr(triangle, "value_col")
)
```

## Arguments

- triangle:

  A \`csfmt_reporting_triangle_v3\`.

- max_delay:

  Number of delay columns (delay 0 .. max_delay-1, in weeks).

- value_col:

  Which value column to reshape (default the triangle's \`value_col\`;
  pass a denominator column to reshape that instead).

## Value

Named list (by time_series_id) of \`list(reference, mat)\`, where
\`mat\` is a reference x delay count matrix (zeros filled within the
observed region).

## See also

Neither package vignette covers this function. It is the densification
step every nowcast engine runs first, so reach for it directly only when
you want the raw reference x delay matrix rather than an ensemble.

Other reporting triangle functions:
[`csfmt_reporting_triangle_v3()`](https://niphr.github.io/csalert/reference/csfmt_reporting_triangle_v3.md)

## Examples

``` r
w <- cstime::dates_by_isoyearweek$isoyearweek
i <- match("2023-01", w)
set.seed(1)
d <- data.table::data.table(
  isoyearweek_reference = w[i + rep(0:39, each = 3)],
  isoyearweek_reporting = w[i + rep(0:39, each = 3) + rep(0:2, 40)],
  numerator = rpois(120, c(30, 15, 5)),
  indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
)
d <- d[isoyearweek_reporting <= w[i + 39]]
tri <- csfmt_reporting_triangle_v3(
  d,
  id_cols = c("indicator_tag", "location_code", "age", "sex")
)

m <- reporting_triangle_matrix(tri, max_delay = 3)
names(m)
#> [1] "d8da72e3fbb5fd29"

# rows are reference weeks, columns are delays 0, 1, 2
head(m[[1]]$reference, 3)
#> [1] "2023-01" "2023-02" "2023-03"
head(m[[1]]$mat, 3)
#>       0  1 2
#> [1,] 26 20 8
#> [2,] 38 16 3
#> [3,] 24 17 6

# the newest weeks are only partly reported: the later delays are still zero
tail(m[[1]]$mat, 3)
#>        0  1 2
#> [38,] 27 21 3
#> [39,] 24 20 0
#> [40,] 20  0 0
```
