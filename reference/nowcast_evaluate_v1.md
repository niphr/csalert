# Score nowcast methods on interval coverage and revision

Replays each method with
[`nowcast_backtest()`](https://niphr.github.io/csalert/reference/nowcast_backtest.md),
and scores every nowcast against the settled truth from
[`nowcast_truth()`](https://niphr.github.io/csalert/reference/nowcast_truth.md).
It returns a row for each horizon and method.

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

  A `csfmt_reporting_triangle_v3` with one series.

- methods:

  One method, or a named list of methods. A method takes a triangle and
  returns a `csfmt_ensemble_v3`. One method gets the name `"method"`.

- max_delay_days:

  The delay horizon in days.

- as_of_weeks, horizons, probs, seed:

  Passed to
  [`nowcast_backtest()`](https://niphr.github.io/csalert/reference/nowcast_backtest.md).
  `probs` MUST include 0.05, 0.25, 0.5, 0.75 and 0.95.

- by:

  The columns to group the scores by.

- thresholds:

  The absolute revisions for the `p_gt_<t>` columns.

## Value

A data.table with one row per group and method:

- `n`: the number of scored forecasts,

- `coverage_50`, `coverage_90`: the share of truths from the 0.25 to the
  0.75 quantile, and from the 0.05 to the 0.95 quantile,

- `median_signed`, `median_abs`, `q05`, `q95`: the median revision, the
  median absolute revision, and the 5% and 95% quantiles of the
  revision,

- `p_gt_<t>`: the share of absolute revisions above each threshold, such
  as `p_gt_25` for 0.25,

- `method`.

A method with no nowcast gives a warning and no rows.

## Details

The revision is `(median - truth) / truth`, over the weeks with a truth
above 0. Every score is a measurement on the replayed weeks, not a
property of a method. The methods replay the same as-of dates with the
same `seed`, so they are paired by forecast. That does not give common
random numbers, which would also need the methods to use their random
numbers in the same way.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
stage 2, which explains how to read each column.

Other nowcast diagnostics:
[`nowcast_backtest()`](https://niphr.github.io/csalert/reference/nowcast_backtest.md),
[`nowcast_censor()`](https://niphr.github.io/csalert/reference/nowcast_censor.md),
[`nowcast_truth()`](https://niphr.github.io/csalert/reference/nowcast_truth.md)

## Examples

``` r
# a small reporting triangle: 30 weeks, each reported 3, 10 and 17 days
# after its Monday
monday <- as.Date("2023-01-02") + 7 * rep(0:29, each = 3)
d <- data.table::data.table(
  isoyearweek_reference = format(monday, "%G-%V"),
  reporting_date = monday + rep(c(3, 10, 17), 30),
  numerator = 10, indicator = "x", location = "n", age = "total", sex = "total")
tri <- csfmt_reporting_triangle_v3(d, id_cols = c("indicator", "location", "age", "sex"))

# one method
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
# a named list of methods, with a `method` column in the result
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
