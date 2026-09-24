# Measure how fast the counts of a reporting triangle arrive

Pools the settled weeks of each series, and returns the share of cases
reported by each delay day, and the mean delay. Use it to choose
`max_delay_days`, and with `period` to see reporting speed up or slow
down.

## Usage

``` r
reporting_completion_v1(
  triangle,
  max_delay_days,
  delay_window = NULL,
  period = c("all", "year", "month")
)
```

## Arguments

- triangle:

  The `csfmt_reporting_triangle_v3` to measure.

- max_delay_days:

  The delay horizon in days, delay day 0 to `max_delay_days - 1`.

- delay_window:

  Use only the settled weeks of about this many recent weeks. It counts
  weeks, not days. `NULL` uses every settled week.

- period:

  `"all"` gives one pooled row. `"year"` and `"month"` give one row per
  calendar year or month of the Thursday of each week, so the year is
  the ISO year.

## Value

A data.table with one row per series and period: the identity columns,
`period`, `n_settled`, `mean_delay`, `complete_by_md`, and `pct_delay0`
to `pct_delay<max_delay_days - 1>`.

- `n_settled`: the settled weeks with a total above 0.

- `mean_delay`: the mean delay in days over the pooled cases. A report
  at delay `max_delay_days` or later counts at `max_delay_days - 1`, so
  it is a lower bound.

- `pct_delayD`: the percentage of pooled cases reported by the end of
  day `D` from the reference Monday, with no interpolation. `pct_delay0`
  is the Monday itself.

## Details

A week is settled when its Monday is at least `max_delay_days - 1` days
before the as-of date. In each period, the function drops a week with a
total of 0. A period with fewer than 3 weeks left gets no row, and no
warning.

## complete_by_md is always 1

`complete_by_md` is the last cumulative share of the total. So it is 1
for every series and period, and `pct_delay<max_delay_days - 1>` is 100.
It does NOT show whether reporting continues after `max_delay_days`.

The last column also holds every later delay. So
`100 - pct_delay<max_delay_days - 2>` is the share reported on the last
day or later. To see the tail, run it again with a larger
`max_delay_days`, and compare `mean_delay` and the `pct_delayD` curve.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
stage 3, which shows how to read each column.

Other reporting completion functions:
[`reporting_completion_trend_v1()`](https://niphr.github.io/csalert/reference/reporting_completion_trend_v1.md)

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

# One pooled curve over 21 delay days. This series reports on days 3, 10 and
# 17 after the reference Monday, so the curve steps on those three days.
rc <- reporting_completion_v1(tri, max_delay_days = 21)
rc[, .(n_settled, mean_delay, pct_delay3, pct_delay10, pct_delay17)]
#>    n_settled mean_delay pct_delay3 pct_delay10 pct_delay17
#>        <int>      <num>      <num>       <num>       <num>
#> 1:        37       6.59       58.9        89.8         100

# there is one pct_delay column per delay day
sum(grepl("^pct_delay", names(rc)))
#> [1] 21

# sliced by month, to show a change in reporting speed
head(
  reporting_completion_v1(tri, max_delay_days = 21, period = "month")[,
    .(period, n_settled, mean_delay, pct_delay10)
  ],
  3
)
#>     period n_settled mean_delay pct_delay10
#>     <char>     <int>      <num>       <num>
#> 1: 2023-01         4       6.48        91.0
#> 2: 2023-02         4       6.48        90.0
#> 3: 2023-03         5       6.72        88.4
```
