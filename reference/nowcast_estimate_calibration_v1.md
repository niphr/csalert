# Estimate a nowcast calibration from a backtest

Learns a per-group interval-scaling correction from past nowcasts scored
against settled truth. See \[nowcast_apply_calibration_v1\] to use it.

## Usage

``` r
nowcast_estimate_calibration_v1(backtest, truth, level = 0.9, by = "horizon")
```

## Arguments

- backtest:

  Long quantile nowcasts (from \[nowcast_backtest\]): \`reference\`, the
  \`by\` column(s), \`quantile_level\`, \`predicted\`.

- truth:

  Settled totals (from \[nowcast_truth\]): \`reference\`, \`truth\`.

- level:

  Central interval level to calibrate on (default 0.9).

- by:

  Grouping column(s) the factor varies over (default "horizon").

## Value

A \`nowcast_calibration\`: per-group raw coverage + scale \`factor\`.

## Details

This is an empirical rescaling, not split conformal. It takes the
ordinary type-7 quantile of the scaled residuals, rather than the
conformal order statistic. It summarises both tails with one symmetric
distance from the median. It therefore carries NO finite-sample coverage
guarantee. Read \`coverage_raw\` as "what this engine did on these
replayed weeks", not as a property of the engine.

## See also

Neither package vignette covers calibration. The example below is its
only worked demonstration.

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

# `coverage_raw` is what happened on these replayed weeks, and `factor` is
# what would have made the 90% interval cover 90% of them. The two horizons
# here fall on opposite sides of nominal, on 17 and 18 scored weeks. That is
# far too little evidence to call the engine over- or under-dispersed. Treat
# a factor as a flag to look into, not a verdict.
nowcast_estimate_calibration_v1(bt, nowcast_truth(tri, max_delay_days = 21))
#> <nowcast_calibration>  90% interval, by horizon
#>   factor > 1 widens (under-dispersed); < 1 narrows (over-dispersed)
#> Key: <horizon>
#>    horizon     n coverage_raw factor
#>      <int> <int>        <num>  <num>
#> 1:       0    17        0.941  0.767
#> 2:       1    18        0.889  1.287
```
