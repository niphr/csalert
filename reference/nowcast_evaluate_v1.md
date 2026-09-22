# Evaluate nowcast method(s): interval coverage + point-estimate revision

Replays each method over the triangle (backtest) and scores it on
interval coverage and point-estimate revision. Coverage asks whether the
intervals are honest; revision asks how much the number will still move.
The scores are stacked into one per-horizon table with a \`method\`
column. Pass a single method or a named list. Every method replays the
same as-of dates from the same starting RNG state, so the comparison is
paired. Coverage is read straight off the interval quantiles, so this
needs no \`scoringutils\`.

## Usage

``` r
nowcast_evaluate_v1(
  triangle,
  methods,
  max_delay_days,
  as_of_weeks = NULL,
  horizons = 1:2,
  probs = c(0.025, 0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 0.95, 0.975),
  by = "horizon",
  thresholds = c(0.25, 0.5),
  seed = NULL
)
```

## Arguments

- triangle:

  A \`csfmt_reporting_triangle_v3\` (single series).

- methods:

  A method \`f(triangle) -\> csfmt_ensemble_v3\`, or a NAMED list of
  them (each with its parameters baked in, e.g. via a closure).

- max_delay_days:

  Delay horizon in DAYS. Passed to \[nowcast_truth\] and
  \[nowcast_backtest\]. \`max_delay_days = 35\` is the 35 days that
  start on the reference week's Monday.

- as_of_weeks, horizons, probs, seed:

  Passed to \[nowcast_backtest\]. \`as_of_weeks\` is a \`Date\` vector.
  Every method gets the same \`seed\`, so each one starts from the same
  RNG state on each as-of date. That pairs the comparison. It does not
  by itself give common random numbers, which would also need the
  methods to consume compatible variates.

- by:

  Grouping for the evaluation summary (default "horizon").

- thresholds:

  Absolute-revision cut-offs to report the exceedance probability for
  (default 25% and 50%).

## Value

A data.table, one row per group x method: \`n\`, interval coverage
(\`coverage_50\`, \`coverage_90\`), the point-estimate revision
(\`median_signed\` bias, \`median_abs\`, \`q05\`/\`q95\` band,
\`p_gt\_\<t\>\` tails) and \`method\`.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
which runs this function on its synthetic triangle and reads the
coverage and revision columns off the result.

Other nowcast diagnostics:
[`nowcast_backtest()`](https://niphr.github.io/csalert/reference/nowcast_backtest.md),
[`nowcast_censor()`](https://niphr.github.io/csalert/reference/nowcast_censor.md),
[`nowcast_truth()`](https://niphr.github.io/csalert/reference/nowcast_truth.md)

## Examples

``` r
# a small reporting triangle: 30 weeks, each reported 3, 10 and 17 days after
# its own Monday
monday <- as.Date("2023-01-02") + 7 * rep(0:29, each = 3)
d <- data.table::data.table(
  isoyearweek_reference = format(monday, "%G-%V"),
  reporting_date = monday + rep(c(3, 10, 17), 30),
  numerator = 10, indicator = "x", location = "n", age = "total", sex = "total")
tri <- csfmt_reporting_triangle_v3(d, id_cols = c("indicator", "location", "age", "sex"))

# one method:
nowcast_evaluate_v1(tri, function(x) nowcast_passthrough_to_ensemble_v1(x, max_delay_days = 21),
                    max_delay_days = 21, horizons = 0:2, seed = 1)
#>    horizon     n coverage_50 coverage_90 median_signed median_abs     q05
#>      <int> <int>       <num>       <num>         <num>      <num>   <num>
#> 1:       2    27           1           1        0.0000     0.0000  0.0000
#> 2:       1    27           0           0       -0.3333     0.3333 -0.3333
#> 3:       0    26           0           0       -0.6667     0.6667 -0.6667
#>        q95 p_gt_25 p_gt_50 method
#>      <num>   <num>   <num> <char>
#> 1:  0.0000       0       0 method
#> 2: -0.3333       1       0 method
#> 3: -0.6667       1       1 method
# several methods, paired by as-of date, stacked with a `method` column:
nowcast_evaluate_v1(tri, max_delay_days = 21, horizons = 0:2, seed = 1, methods = list(
  passthrough = function(x) nowcast_passthrough_to_ensemble_v1(x, max_delay_days = 21)))
#>    horizon     n coverage_50 coverage_90 median_signed median_abs     q05
#>      <int> <int>       <num>       <num>         <num>      <num>   <num>
#> 1:       2    27           1           1        0.0000     0.0000  0.0000
#> 2:       1    27           0           0       -0.3333     0.3333 -0.3333
#> 3:       0    26           0           0       -0.6667     0.6667 -0.6667
#>        q95 p_gt_25 p_gt_50      method
#>      <num>   <num>   <num>      <char>
#> 1:  0.0000       0       0 passthrough
#> 2: -0.3333       1       0 passthrough
#> 3: -0.6667       1       1 passthrough
```
