# Empirical reporting-completion summary from a reporting triangle

Empirical reporting-completion summary from a reporting triangle

## Usage

``` r
reporting_completion_v1(
  triangle,
  max_delay,
  delay_window = NULL,
  period = c("all", "year", "month")
)
```

## Arguments

- triangle:

  A \`csfmt_reporting_triangle_v3\`.

- max_delay:

  Delay horizon in weeks.

- delay_window:

  Optional: use only settled weeks within roughly this many weeks
  (drift-aware). \`NULL\` uses all settled weeks. Ignored for the shape
  of \`period\` stratification, which slices time itself.

- period:

  Time stratification of the settled weeks, by the calendar year / month
  of each week's Thursday: \`"all"\` (one pooled curve, default),
  \`"year"\`, or \`"month"\` (one row per period). Use
  \`"year"\`/\`"month"\` to see whether completion time is trending up
  or down.

## Value

One row per series (and per period when stratified): identity columns +
\`period\` + \`n_settled\`, \`mean_delay\`, \`complete_by_md\`, and
\`pct_w1\`..\`pct_w\<max_delay\>\` (the pooled % of cases reported after
that many weeks observed – the delay ECDF, no interpolation). Every one
of these is computed AFTER delays \`\>= max_delay\` have been discarded,
so they describe the cases that arrive within the horizon, not all
eventual cases.

## complete_by_md is always 1

\`complete_by_md\` is the last cumulative fraction of a total that was
itself summed over the truncated delay axis, so it equals 1 for every
series and every period, and \`pct_w\<max_delay\>\` equals 100. It does
NOT measure whether reporting continues past \`max_delay\`. To look for
a tail, re-run with a larger \`max_delay\` and compare \`mean_delay\`
and the \`pct_wN\` curve.

## See also

[`vignette("nowcasting", package = "csalert")`](https://niphr.github.io/csalert/articles/nowcasting.md),
which runs this function on its synthetic triangle.

Other reporting completion functions:
[`reporting_completion_trend_v1()`](https://niphr.github.io/csalert/reference/reporting_completion_trend_v1.md)

## Examples

``` r
w <- cstime::dates_by_isoyearweek$isoyearweek
i <- match("2023-01", w)
set.seed(1)
d <- data.table::data.table(
  isoyearweek_reference = w[i + rep(0:39, each = 3)],
  isoyearweek_reporting = w[i + rep(0:39, each = 3) + rep(0:2, 40)],
  numerator = rpois(120, c(30, 15, 5)),
  indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
)
d <- d[isoyearweek_reporting <= w[i + 39]]
tri <- csfmt_reporting_triangle_v3(
  d,
  id_cols = c("indicator_tag", "location_code", "age", "sex")
)

# one pooled curve: pct_w1 is the share in after one week observed
reporting_completion_v1(tri, max_delay = 3)
#>    indicator_tag location_code    age    sex period n_settled mean_delay
#>           <char>        <char> <char> <char> <char>     <int>      <num>
#> 1:             x        nation  total  total    all        38       0.51
#>    complete_by_md pct_w1 pct_w2 pct_w3
#>             <num>  <num>  <num>  <num>
#> 1:              1   58.8   89.9    100

# sliced by month, to expose drift in how fast reporting arrives
head(reporting_completion_v1(tri, max_delay = 3, period = "month"), 3)
#>    indicator_tag location_code    age    sex  period n_settled mean_delay
#>           <char>        <char> <char> <char>  <char>     <int>      <num>
#> 1:             x        nation  total  total 2023-01         4       0.50
#> 2:             x        nation  total  total 2023-02         4       0.50
#> 3:             x        nation  total  total 2023-03         5       0.53
#>    complete_by_md pct_w1 pct_w2 pct_w3
#>             <num>  <num>  <num>  <num>
#> 1:              1   59.3   91.0    100
#> 2:              1   60.2   90.0    100
#> 3:              1   58.5   88.4    100
```
