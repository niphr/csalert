# Reporting-completion trend: the delay curve by year and recent months

Convenience over \[reporting_completion\]: the completion curve sliced
by calendar \`year\` (all years) and by \`month\` (the most recent
\`n_months\`, per series), stacked with a \`scope\` column. One table
that shows whether reporting is speeding up or slowing down over time.

## Usage

``` r
reporting_completion_trend_v1(triangle, max_delay, n_months = 12L)
```

## Arguments

- triangle:

  A \`csfmt_reporting_triangle_v3\`.

- max_delay:

  Delay horizon in weeks.

- n_months:

  Keep this many most-recent months per series. Default 12.

## Value

A data.table: the \[reporting_completion\] columns plus a \`scope\`
column ("year"/"month"), the year rows followed by the last-\`n_months\`
month rows. Empty when no series has enough settled data.

## Examples

``` r
w <- cstime::dates_by_isoyearweek$isoyearweek; i <- match("2023-01", w)
d <- data.table::data.table(
  isoyearweek_reference = w[i + rep(0:39, each = 3)],
  isoyearweek_reporting = w[i + rep(0:39, each = 3) + rep(0:2, 40)],
  numerator = 10, indicator = "x", location = "n", age = "total", sex = "total")
tri <- csfmt_reporting_triangle_v3(d, id_cols = c("indicator", "location", "age", "sex"))
reporting_completion_trend_v1(tri, max_delay = 3, n_months = 6)
#>    indicator location    age    sex  period n_settled mean_delay complete_by_md
#>       <char>   <char> <char> <char>  <char>     <int>      <num>          <num>
#> 1:         x        n  total  total    2023        40          1              1
#> 2:         x        n  total  total 2023-04         4          1              1
#> 3:         x        n  total  total 2023-05         4          1              1
#> 4:         x        n  total  total 2023-06         5          1              1
#> 5:         x        n  total  total 2023-07         4          1              1
#> 6:         x        n  total  total 2023-08         5          1              1
#> 7:         x        n  total  total 2023-09         4          1              1
#>    pct_w1 pct_w2 pct_w3  scope
#>     <num>  <num>  <num> <char>
#> 1:   33.3   66.7    100   year
#> 2:   33.3   66.7    100  month
#> 3:   33.3   66.7    100  month
#> 4:   33.3   66.7    100  month
#> 5:   33.3   66.7    100  month
#> 6:   33.3   66.7    100  month
#> 7:   33.3   66.7    100  month
```
