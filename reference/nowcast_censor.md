# Censor a reporting triangle to what was known "as of" a past week

Keeps only cells reported on or before \`as_of\` and rebuilds the
triangle, so its as-of boundary and delay structure are exactly what an
engine would have seen at that week. The basis for replay-based
backtesting.

## Usage

``` r
nowcast_censor(triangle, as_of)
```

## Arguments

- triangle:

  A \`csfmt_reporting_triangle_v3\`.

- as_of:

  An ISO-week string; cells reported after it are dropped.

## Value

A \`csfmt_reporting_triangle_v3\` censored to \`as_of\`.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md)
calls this function directly in its validation stage, to rebuild what
was known as of an earlier week.
[`nowcast_evaluate_v1`](https://niphr.github.io/csalert/reference/nowcast_evaluate_v1.md)
censors for you when you do not need the censored triangle itself.

Other nowcast diagnostics:
[`nowcast_backtest()`](https://niphr.github.io/csalert/reference/nowcast_backtest.md),
[`nowcast_evaluate_v1()`](https://niphr.github.io/csalert/reference/nowcast_evaluate_v1.md),
[`nowcast_truth()`](https://niphr.github.io/csalert/reference/nowcast_truth.md)

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

# rewind to what was known nine weeks earlier
past <- nowcast_censor(tri, as_of = w[i + 30])
c(now = attr(tri, "as_of"), then = attr(past, "as_of"))
#>       now      then 
#> "2023-40" "2023-31" 
c(rows_now = nrow(tri), rows_then = nrow(past))
#>  rows_now rows_then 
#>       117        90 
```
