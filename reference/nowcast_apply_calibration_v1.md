# Rescale quantile nowcasts by a calibration factor

Moves every quantile away from the median, or toward it, by the factor
of its group. The median does not move, and a group with no factor
passes through.

## Usage

``` r
nowcast_apply_calibration_v1(x, calibration)
```

## Arguments

- x:

  Long quantile nowcasts with `reference`, the `by` columns,
  `quantile_level` and `predicted`, such as the output of
  [`nowcast_backtest()`](https://niphr.github.io/csalert/reference/nowcast_backtest.md).

- calibration:

  A `nowcast_calibration` from
  [`nowcast_estimate_calibration_v1()`](https://niphr.github.io/csalert/reference/nowcast_estimate_calibration_v1.md).

## Value

A copy of `x` with `predicted` rescaled.

## Details

The rescaled interval covers about `level` of the backtest that the
factor came from, not exactly. The type-7 quantile interpolates, and
each tail moves by its own distance from the median. On future weeks
there is no guarantee.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
stage 2.

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

# the median stays, and the width of the interval changes by the factor
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
