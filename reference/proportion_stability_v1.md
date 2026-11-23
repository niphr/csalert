# Measure how stable a proportion is at each delay day of a reporting triangle

For each delay day, compares the proportion of numerator to denominator
seen at that day with its settled value. Use it next to
[`reporting_completion_v1()`](https://niphr.github.io/csalert/reference/reporting_completion_v1.md)
to see how many recent weeks of a proportion are reliable.

## Usage

``` r
proportion_stability_v1(
  triangle,
  max_delay_days,
  denominator_col,
  delay_window = NULL
)
```

## Arguments

- triangle:

  The `csfmt_reporting_triangle_v3` to measure. The value column of the
  triangle is the numerator.

- max_delay_days:

  The delay horizon in days, delay day 0 to `max_delay_days - 1`.

- denominator_col:

  The name of the column of `triangle` that holds the denominator.

- delay_window:

  Use only the settled weeks of about this many recent weeks. It counts
  weeks, not days. `NULL` uses every settled week.

## Value

A data.table with one row per series and delay day: the identity
columns, `n_settled`, `n_eval`, `delay`, `pct_count`, `prop_relerr_p50`,
`prop_relerr_p90`, `prop_abserr_p50` and `prop_abserr_p90`.

- `n_settled`: the settled weeks that the function uses.

- `n_eval`: the weeks of `n_settled` with a cumulative denominator above
  0 at delay day `delay`.

- `delay`: the delay day, an integer from 0 to `max_delay_days - 1`.

- `pct_count`: the pooled cumulative numerator at `delay`, in percent of
  the pooled settled numerator, over the `n_settled` weeks. It has 1
  decimal.

- `prop_relerr_p50`, `prop_relerr_p90`: the median and the 90th
  percentile of `100 * abs(p_d / p - 1)`, in percent of the settled
  proportion.

- `prop_abserr_p50`, `prop_abserr_p90`: the median and the 90th
  percentile of `100 * abs(p_d - p)`, in percentage points.

The four error columns use `stats::quantile(type = 7)` over the `n_eval`
weeks, and have 2 decimals. They are `NA` where `n_eval` is 0. The
result is an empty data.table when no series has 3 weeks to use.

## Details

Both counts come from
[`reporting_triangle_matrix()`](https://niphr.github.io/csalert/reference/reporting_triangle_matrix.md).
The settled value of a week is its cumulative count at delay day
`max_delay_days - 1`. A report at delay `max_delay_days` or later is not
in it. This is the convention of
[`delay_distribution_v1()`](https://niphr.github.io/csalert/reference/delay_distribution_v1.md).
It is different from
[`reporting_completion_v1()`](https://niphr.github.io/csalert/reference/reporting_completion_v1.md),
which adds the reports past the horizon to the last delay day.

A week is settled when its Monday is at least `max_delay_days - 1` days
before the as-of date, `attr(triangle, "as_of")`. A settled week is used
only if its settled numerator and its settled denominator are both above
0. A series with fewer than 3 such weeks gets no rows, and no warning.

At delay day `d`, a week has the proportion `p_d`, its cumulative
numerator divided by its cumulative denominator. Its settled proportion
is `p`. A week with a cumulative denominator of 0 at day `d` is not used
at that day.

## See also

Other reporting completion functions:
[`reporting_completion_trend_v1()`](https://niphr.github.io/csalert/reference/reporting_completion_trend_v1.md),
[`reporting_completion_v1()`](https://niphr.github.io/csalert/reference/reporting_completion_v1.md)

## Examples

``` r
monday <- as.Date("2023-01-02") + 7 * rep(0:19, each = 2)
d <- data.table::data.table(
  isoyearweek_reference = format(monday, "%G-%V"),
  reporting_date = monday + rep(c(1, 8), 20),
  numerator = rep(c(3, 1), 20),
  denominator = rep(c(10, 10), 20),
  indicator = "x", location = "nation", age = "total", sex = "total"
)
tri <- csfmt_reporting_triangle_v3(
  d,
  id_cols = c("indicator", "location", "age", "sex")
)

# The proportion is 0.3 on day 1 and 0.2 when it settles on day 8, so the
# relative error is 50 percent from day 1 to day 7.
ps <- proportion_stability_v1(tri, max_delay_days = 9, "denominator")
ps[, .(delay, n_eval, pct_count, prop_relerr_p50, prop_abserr_p50)]
#>    delay n_eval pct_count prop_relerr_p50 prop_abserr_p50
#>    <int>  <int>     <num>           <num>           <num>
#> 1:     0      0         0              NA              NA
#> 2:     1     20        75              50              10
#> 3:     2     20        75              50              10
#> 4:     3     20        75              50              10
#> 5:     4     20        75              50              10
#> 6:     5     20        75              50              10
#> 7:     6     20        75              50              10
#> 8:     7     20        75              50              10
#> 9:     8     20       100               0               0
```
