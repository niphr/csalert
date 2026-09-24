# Reporting speed by year and by recent month, in one table

Stacks
[`reporting_completion_v1()`](https://niphr.github.io/csalert/reference/reporting_completion_v1.md)
by year, and by month for the latest `n_months` months of each series,
so one table shows reporting speed up or slow down.

## Usage

``` r
reporting_completion_trend_v1(triangle, max_delay_days, n_months = 12L)
```

## Arguments

- triangle:

  The `csfmt_reporting_triangle_v3` to measure.

- max_delay_days:

  The delay horizon in days.

- n_months:

  The number of latest months to keep for each series.

## Value

A data.table with the columns of
[`reporting_completion_v1()`](https://niphr.github.io/csalert/reference/reporting_completion_v1.md)
and `scope`, `"year"` or `"month"`, with the year rows first. It is
empty when no series has enough settled weeks.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
stage 3.

Other reporting completion functions:
[`reporting_completion_v1()`](https://niphr.github.io/csalert/reference/reporting_completion_v1.md)

## Examples

``` r
monday <- as.Date("2023-01-02") + 7 * rep(0:39, each = 3)
d <- data.table::data.table(
  isoyearweek_reference = format(monday, "%G-%V"),
  reporting_date = monday + rep(c(3, 10, 17), 40),
  numerator = 10, indicator = "x", location = "n", age = "total", sex = "total")
tri <- csfmt_reporting_triangle_v3(d, id_cols = c("indicator", "location", "age", "sex"))
reporting_completion_trend_v1(tri, max_delay_days = 21, n_months = 6)[,
  .(scope, period, n_settled, mean_delay)]
#>     scope  period n_settled mean_delay
#>    <char>  <char>     <int>      <num>
#> 1:   year    2023        39         10
#> 2:  month 2023-04         4         10
#> 3:  month 2023-05         4         10
#> 4:  month 2023-06         5         10
#> 5:  month 2023-07         4         10
#> 6:  month 2023-08         5         10
#> 7:  month 2023-09         4         10
```
