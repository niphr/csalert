# The Monday that starts an ISO week

Returns the Monday that starts each ISO week, as a \`Date\`. Every delay
in a reporting triangle is the number of days from this Monday to the
reporting date.

## Usage

``` r
isoyearweek_week_start(isoyearweek)
```

## Arguments

- isoyearweek:

  Character vector of ISO weeks, written \`"YYYY-WW"\`, for example
  \`"2026-01"\`.

## Value

A \`Date\` vector with one element per element of \`isoyearweek\`. A
value that is not an ISO week in \`cstime::dates_by_isoyearweek\` gives
\`NA\`.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
which measures every delay and every age in days from this Monday.

Other reporting triangle functions:
[`csfmt_reporting_triangle_v3()`](https://niphr.github.io/csalert/reference/csfmt_reporting_triangle_v3.md),
[`reporting_triangle_matrix()`](https://niphr.github.io/csalert/reference/reporting_triangle_matrix.md)

## Examples

``` r
# ISO week 2026-01 starts on Monday 2025-12-29
isoyearweek_week_start(c("2026-01", "2026-02"))
#> [1] "2025-12-29" "2026-01-05"

# a report on 2026-01-08 has delay day 10 in reference week 2026-01
as.Date("2026-01-08") - isoyearweek_week_start("2026-01")
#> Time difference of 10 days

# a string that is not an ISO week gives NA
isoyearweek_week_start("2026-99")
#> [1] NA
```
