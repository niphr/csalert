# The settled total of each reference week

Sums the counts of each settled reference week, the truth that a
backtest scores a nowcast against. A report at delay `max_delay_days` or
later counts in the last delay day, so it is in the total.

## Usage

``` r
nowcast_truth(triangle, max_delay_days)
```

## Arguments

- triangle:

  A `csfmt_reporting_triangle_v3` with one series.

- max_delay_days:

  The delay horizon in days. 35 is the 35 days from the reference
  Monday. The 5 weekly delay columns of the older format had the same
  span.

## Value

A data.table with `reference`, the ISO week, and `truth`, one row per
settled week.

## Details

A week is settled when its Monday is at least `max_delay_days - 1` days
before the as-of date. With `max_delay_days = 21`, the newest settled
week starts 20 days before the as-of date, not 21. A settled week is not
final: a later report still adds to its total.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
stage 2.

Other nowcast diagnostics:
[`nowcast_backtest()`](https://niphr.github.io/csalert/reference/nowcast_backtest.md),
[`nowcast_censor()`](https://niphr.github.io/csalert/reference/nowcast_censor.md),
[`nowcast_evaluate_v1()`](https://niphr.github.io/csalert/reference/nowcast_evaluate_v1.md)

## Examples

``` r
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

truth <- nowcast_truth(tri, max_delay_days = 21)

# the newest weeks are not settled yet, so they have no row
tail(truth, 3)
#>    reference truth
#>       <char> <num>
#> 1:   2023-35    44
#> 2:   2023-36    44
#> 3:   2023-37    43
c(reference_weeks = 40L, settled = nrow(truth))
#> reference_weeks         settled 
#>              40              37 
```
