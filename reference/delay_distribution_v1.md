# Estimate the delay distribution of a reporting triangle

Estimates the probability that a case is reported on each delay day,
from 0 to `max_delay_days - 1`. The estimate uses every reference week,
and corrects for the weeks that are not fully reported yet.

## Usage

``` r
delay_distribution_v1(x, max_delay_days)
```

## Arguments

- x:

  A `csfmt_reporting_triangle_v3` with one series. With more than one
  `time_series_id`, the function stops with an error that names the id
  columns of `x`.

- max_delay_days:

  The delay horizon in days, delay day 0 to `max_delay_days - 1`.

## Value

A data.table with one row per delay day and four columns:

- `delay`: the delay day, an integer from 0 to `max_delay_days - 1`.

- `day_after`: the integer `delay - 6`. Day 1 is the Monday after the
  reference week.

- `week_after`: the integer `delay / 7` where `delay` is a multiple of
  7, and `NA` on every other day.

- `p`: the probability of a report on delay day `delay`. With
  `max_delay_days = 1`, `p` is 1.

## Details

The function uses the rows of
[`reporting_triangle_matrix()`](https://niphr.github.io/csalert/reference/reporting_triangle_matrix.md)
whose reference Monday is on or before the as-of date,
`attr(x, "as_of")`. `age_days` is the number of days from that Monday to
the as-of date. A row has seen delay days 0 to `n_seen - 1`, with
`n_seen = pmin(age_days + 1, max_delay_days)`.

The product-limit estimate starts at the last delay day, where the
cumulative distribution `F` is 1. Then `F(d - 1) / F(d)` is the count
reported by delay `d - 1`, divided by the count reported by delay `d`.
Both sums use only the rows that have seen delay `d`. Where the count by
delay `d` is 0, `F(d - 1) = F(d)`. A report at delay `max_delay_days` or
later is not in the estimate, so `p` is conditional on a report within
the horizon.

The function does not choose a window of weeks. It also keeps the weeks
with a reporting outage, which
[`outage_weeks_v1()`](https://niphr.github.io/csalert/reference/outage_weeks_v1.md)
finds. To leave weeks out, filter `x` before the call. A triangle
filtered with `[` keeps its as-of date.

## Delay convention

Delay day 0 is the Monday of the reference ISO week, and delay `d` is
`d` days after it. NorSySS readers count from the end of the week
instead. The columns `day_after` and `week_after` give their count.

- `day_after` k is the k-th day after the week, so day 1 is the Monday
  after the week. The values from -6 to 0 are days inside the week: -6
  is its Monday, and 0 is the Sunday that ends it.

- `week_after` k is the Monday k weeks after the week, so week 1 is day
  1 and week 2 is day 8.

For example, week 2026-46 starts on Monday 2026-11-09. Delay 7 is Monday
2026-11-16, which is day 1 and week 1. Delay 14 is day 8 and week 2. A
horizon of 63 days, 9 weeks, puts week 8 at delay 56, inside the
horizon.

## See also

[`reporting_completion_v1()`](https://niphr.github.io/csalert/reference/reporting_completion_v1.md),
which pools only the weeks old enough to be fully reported.

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

# this series reports on days 3, 10 and 17 after the reference Monday
dd <- delay_distribution_v1(tri, max_delay_days = 21)
dd[p > 0]
#>    delay day_after week_after         p
#>    <int>     <int>      <int>     <num>
#> 1:     3        -3         NA 0.5850863
#> 2:    10         4         NA 0.3143283
#> 3:    17        11         NA 0.1005854

# the last 20 reference weeks only
delay_distribution_v1(tri[isoyearweek_reference >= "2023-21"], 21)[p > 0]
#>    delay day_after week_after         p
#>    <int>     <int>      <int>     <num>
#> 1:     3        -3         NA 0.5773124
#> 2:    10         4         NA 0.3210895
#> 3:    17        11         NA 0.1015982
```
