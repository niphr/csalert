# Apply a nowcast calibration to quantile predictions

Rescales each quantile by moving it away from (or toward) the median by
the learned per-group \`factor\`. By construction the rescaled central
interval covers \`level\` of the BACKTEST the factor was learned on;
that is not a guarantee about future weeks, and the median is left
unchanged. Groups with no learned factor (e.g. an unseen horizon) pass
through unchanged.

## Usage

``` r
nowcast_apply_calibration_v1(x, calibration)
```

## Arguments

- x:

  Long quantile predictions (\`reference\`, the calibration's \`by\`
  column(s), \`quantile_level\`, \`predicted\`) – e.g. a fresh
  \[nowcast_backtest\] output or a melted collapse.

- calibration:

  A \`nowcast_calibration\` from \[nowcast_estimate_calibration_v1\].

## Value

\`x\` with \`predicted\` recalibrated.

## See also

Neither package vignette covers calibration. The example below is its
only worked demonstration.

Other nowcast calibration functions:
[`nowcast_estimate_calibration_v1()`](https://niphr.github.io/csalert/reference/nowcast_estimate_calibration_v1.md),
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
  horizons = 0:1, probs = c(0.05, 0.5, 0.95), seed = 1
)
cal <- nowcast_estimate_calibration_v1(bt, nowcast_truth(tri, max_delay_days = 21))

adj <- nowcast_apply_calibration_v1(bt, cal)

# the median is untouched; the other two quantiles move toward or away from
# it, so the interval width changes by the learned factor
width <- function(x) {
  x[horizon == 0, .(width = diff(range(predicted))), by = reference][1:3]
}
width(bt)
#>    reference    width
#>       <char>    <num>
#> 1:   2023-21 16.70415
#> 2:   2023-22 14.79321
#> 3:   2023-23 19.03695
width(adj)
#>    reference    width
#>       <char>    <num>
#> 1:   2023-21 12.81208
#> 2:   2023-22 11.34639
#> 3:   2023-23 14.60134
```
