# The settled (eventually-observed) total per reference week

Sums each reference week's counts over every non-negative delay, the
quantity a nowcast is trying to predict. A report at delay
\`max_delay_days\` or later counts in the last delay day,
\`max_delay_days - 1\`, so it is inside this total. Keeps only the weeks
old enough to be settled. A settled week's Monday is at least
\`max_delay_days - 1\` days before the triangle's as-of date. That bound
is one lower than it may read. With \`max_delay_days = 21\`, the newest
settled week starts 20 days before the as-of date, not 21. A settled
week is not final. A report that arrives after the as-of date has a
delay of \`max_delay_days\` or more, and it still adds to the week's
total.

## Usage

``` r
nowcast_truth(triangle, max_delay_days)
```

## Arguments

- triangle:

  A \`csfmt_reporting_triangle_v3\` (single series).

- max_delay_days:

  Delay horizon in DAYS: delay day 0 to \`max_delay_days - 1\`.
  \`max_delay_days = 35\` is the 35 days that start on the reference
  week's Monday. It matches the 5 weekly delay columns of the pre-Date
  format.

## Value

A data.table \`reference\`, \`truth\`.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md)
calls this function directly in its validation stage to obtain settled
truth.
[`nowcast_evaluate_v1`](https://niphr.github.io/csalert/reference/nowcast_evaluate_v1.md)
calls it for you when you only want the scores.

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

# the newest weeks are missing: they are not settled yet, so they have no
# truth to be scored against
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
