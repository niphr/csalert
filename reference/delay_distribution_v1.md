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

A data.table with one row per delay day: `delay`, an integer from 0 to
`max_delay_days - 1`, and `p`, its probability. With
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
#>    delay         p
#>    <int>     <num>
#> 1:     3 0.5850863
#> 2:    10 0.3143283
#> 3:    17 0.1005854

# the last 20 reference weeks only
delay_distribution_v1(tri[isoyearweek_reference >= "2023-21"], 21)[p > 0]
#>    delay         p
#>    <int>     <num>
#> 1:     3 0.5773124
#> 2:    10 0.3210895
#> 3:    17 0.1015982
```
