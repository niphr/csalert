# Cut a reporting triangle back to what was known on a past date

Keeps the cells reported on or before `as_of`, and rebuilds the
triangle. That is exactly what an engine saw on that date only when the
reporting system never corrects or deletes a count.

## Usage

``` r
nowcast_censor(triangle, as_of)
```

## Arguments

- triangle:

  The `csfmt_reporting_triangle_v3` to cut back.

- as_of:

  A `Date`. Any other class is an error. R compares
  `reporting date <= as_of` by the type of `as_of`, so the number 18262
  would cut to 2020-01-01 with no warning. A date with no report on or
  before it is an error.

## Value

A `csfmt_reporting_triangle_v3`. Its as-of boundary is the newest
reporting date that remains.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
stage 2.

Other nowcast diagnostics:
[`nowcast_backtest()`](https://niphr.github.io/csalert/reference/nowcast_backtest.md),
[`nowcast_evaluate_v1()`](https://niphr.github.io/csalert/reference/nowcast_evaluate_v1.md),
[`nowcast_truth()`](https://niphr.github.io/csalert/reference/nowcast_truth.md)

## Examples

``` r
# 40 reference weeks, each reported 3, 10 and 17 days after its Monday
monday <- as.Date("2023-01-02") + 7 * rep(0:39, each = 3)
set.seed(1)
d <- data.table::data.table(
  isoyearweek_reference = format(monday, "%G-%V"),
  reporting_date = monday + rep(c(3, 10, 17), 40),
  numerator = rpois(120, c(30, 15, 5)),
  indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
)
d <- d[reporting_date <= as.Date("2023-01-02") + 7 * 39 + 6]
tri <- csfmt_reporting_triangle_v3(
  d,
  id_cols = c("indicator_tag", "location_code", "age", "sex")
)

# go back to what was known nine weeks earlier
past <- nowcast_censor(tri, as_of = as.Date("2023-01-02") + 7 * 30 + 6)
c(now = attr(tri, "as_of"), then = attr(past, "as_of"))
#>          now         then 
#> "2023-10-05" "2023-08-03" 
c(rows_now = nrow(tri), rows_then = nrow(past))
#>  rows_now rows_then 
#>       117        90 
```
