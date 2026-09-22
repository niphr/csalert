# Empirical reporting-completion summary from a reporting triangle

Empirical reporting-completion summary from a reporting triangle

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

  A \`csfmt_reporting_triangle_v3\`.

- max_delay_days:

  Delay horizon in DAYS: delay day 0 to \`max_delay_days - 1\`.
  \`max_delay_days = 35\` is the 35 days that start on the reference
  week's Monday, and matches the 5 weekly delay columns of the pre-Date
  format.

- delay_window:

  Optional: use only settled weeks within roughly this many WEEKS
  (drift-aware). This one is weeks, not days, because it selects
  reference weeks and the reference axis is still an ISO week. \`NULL\`
  uses all settled weeks. Ignored for the shape of \`period\`
  stratification, which slices time itself.

- period:

  Time stratification of the settled weeks, by the calendar year or
  month of each week's Thursday. Choose \`"all"\` (one pooled curve,
  default), \`"year"\`, or \`"month"\` (one row per period). Use
  \`"year"\` or \`"month"\` to see whether completion time is trending
  up or down.

## Value

One row per series, and per period when stratified. The columns are
identity columns + \`period\` + \`n_settled\`, \`mean_delay\`,
\`complete_by_md\`, and
\`pct_delay0\`..\`pct_delay\<max_delay_days-1\>\`. There are exactly
\`max_delay_days\` of those \`pct_delayD\` columns. Each one is the
pooled % of cases reported by the end of day reference Monday + D, the
delay ECDF, no interpolation. \`pct_delay0\` is the reference week's own
Monday. \`mean_delay\` is in DAYS. Every one of these is computed AFTER
delays \`\>= max_delay_days\` are discarded. They describe the cases
that arrive within the horizon, not all eventual cases.

## complete_by_md is always 1

\`complete_by_md\` is the last cumulative fraction of a total that was
itself summed over the truncated delay axis. So it equals 1 for every
series and every period, and \`pct_delay\<max_delay_days-1\>\` equals
100. It does NOT measure whether reporting continues past
\`max_delay_days\`. To look for a tail, re-run with a larger
\`max_delay_days\` and compare \`mean_delay\` and the \`pct_delayD\`
curve.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
which runs this function on its synthetic triangle.

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

# one pooled curve over 21 delay days. This series reports on days 3, 10 and
# 17 after the reference Monday, so the curve steps at those three days.
rc <- reporting_completion_v1(tri, max_delay_days = 21)
rc[, .(n_settled, mean_delay, pct_delay3, pct_delay10, pct_delay17)]
#>    n_settled mean_delay pct_delay3 pct_delay10 pct_delay17
#>        <int>      <num>      <num>       <num>       <num>
#> 1:        37       6.59       58.9        89.8         100

# there is one pct_delay column per delay day
sum(grepl("^pct_delay", names(rc)))
#> [1] 21

# sliced by month, to expose drift in how fast reporting arrives
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
