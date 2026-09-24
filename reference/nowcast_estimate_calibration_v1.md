# Estimate an interval scaling factor from a backtest

Measures, for each group, the factor that would have made the central
`level` interval of past nowcasts cover `level` of their settled truths.
Use it to check an engine.
[`nowcast_apply_calibration_v1()`](https://niphr.github.io/csalert/reference/nowcast_apply_calibration_v1.md)
applies it if you choose to.

## Usage

``` r
nowcast_estimate_calibration_v1(backtest, truth, level = 0.9, by = "horizon")
```

## Arguments

- backtest:

  The output of
  [`nowcast_backtest()`](https://niphr.github.io/csalert/reference/nowcast_backtest.md).
  The function uses the `quantile_level` nearest to each end of the
  interval and to the median.

- truth:

  The output of
  [`nowcast_truth()`](https://niphr.github.io/csalert/reference/nowcast_truth.md).

- level:

  The central interval level.

- by:

  The columns that the factor varies over.

## Value

A `nowcast_calibration`: a list with `level`, `by` and `table`, which
has the `by` columns, `n`, `coverage_raw`, the share of truths inside
the interval, and `factor`.

## Details

The factor is the type-7 `level` quantile of
`|truth - median| / halfwidth`, where `halfwidth` is half the width of
the interval. Above 1, the intervals were too narrow, and below 1 too
wide.

This is an empirical rescaling, not split conformal. It uses the type-7
quantile, not the order statistic that a conformal argument needs, and
one symmetric distance for both tails. So it carries NO finite-sample
coverage guarantee. `coverage_raw` is what the engine did on these
replayed weeks, not a property of the engine.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
stage 2, which measures the coverage that the factor corrects.

Other nowcast calibration functions:
[`nowcast_apply_calibration_v1()`](https://niphr.github.io/csalert/reference/nowcast_apply_calibration_v1.md),
[`print.nowcast_calibration()`](https://niphr.github.io/csalert/reference/print.nowcast_calibration.md)

## Examples

``` r
# 40 reference weeks, each reported 3, 10 and 17 days after its Monday
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

method <- function(x) nowcast_delay_ecdf_v1(x, max_delay_days = 21, n_sim = 200)
bt <- nowcast_backtest(
  tri, method,
  max_delay_days = 21,
  as_of_weeks = as.Date("2023-01-02") + 7 * (20:38) + 6,
  horizons = 0:1, seed = 1
)

# The two horizons fall on opposite sides of 0.9, on 17 and 18 scored weeks.
# That is too little evidence to call the engine over- or under-dispersed, so
# read a factor as a reason to look closer, not as a verdict.
nowcast_estimate_calibration_v1(bt, nowcast_truth(tri, max_delay_days = 21))
#> <nowcast_calibration>  90% interval, by horizon
#>   factor > 1 widens (under-dispersed); < 1 narrows (over-dispersed)
#> Key: <horizon>
#>    horizon     n coverage_raw factor
#>      <int> <int>        <num>  <num>
#> 1:       0    17        0.941  0.767
#> 2:       1    18        0.889  1.287
```
