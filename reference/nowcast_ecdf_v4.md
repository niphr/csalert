# Nowcast a reporting triangle from the delay pattern of settled weeks

Completes each incomplete reference week from a pool of settled
reference weeks. Each draw is the count observed so far, times a
quantile of the completion ratios that the pool shows at the same delay
day.

## Usage

``` r
nowcast_ecdf_v4(
  x,
  max_delay_days,
  seed,
  n_sim = 1000,
  denominator_col = NULL,
  delay_window = 26
)
```

## Arguments

- x:

  The `csfmt_reporting_triangle_v4` to nowcast.

- max_delay_days:

  The delay horizon in days, delay day 0 to `max_delay_days - 1`. The
  nowcast estimates the count reported within it.

- seed:

  The seed of the draws, one whole number.

- n_sim:

  The number of draws.

- denominator_col:

  A denominator column to nowcast on the same draws. Its observed total
  goes to `$data` as `<denominator_col>_observed`.

- delay_window:

  The span, in weeks, of the settled weeks in the pool. `NULL` uses
  every settled week.

## Value

A `csfmt_ensemble_v4` with one row per reference week. `$draws` holds
one matrix with `n_sim` columns per measure, named by the measure.
`$data` holds `original`, the observed total, which includes every
report at delay `max_delay_days` or later.

## Details

The method is that of
[`nowcast_delay_ecdf_v1()`](https://niphr.github.io/csalert/reference/nowcast_delay_ecdf_v1.md).
With the same triangle and the same seed, the draws are identical. The
draw matrix has the name of `value_col`, with no suffix. The function
sets the seed itself and then restores the random-number state of the
caller.

## See also

Other v4 functions:
[`as_ensemble_v4()`](https://niphr.github.io/csalert/reference/as_ensemble_v4.md),
[`csfmt_ensemble_v4()`](https://niphr.github.io/csalert/reference/csfmt_ensemble_v4.md),
[`csfmt_reporting_triangle_v4()`](https://niphr.github.io/csalert/reference/csfmt_reporting_triangle_v4.md),
[`ens_add_rate_v4()`](https://niphr.github.io/csalert/reference/ens_add_rate_v4.md),
[`ens_compress_v4()`](https://niphr.github.io/csalert/reference/ens_compress_v4.md),
[`mem_thresholds_v4()`](https://niphr.github.io/csalert/reference/mem_thresholds_v4.md),
[`nowcast_passthrough_v4()`](https://niphr.github.io/csalert/reference/nowcast_passthrough_v4.md),
[`print.csfmt_ensemble_v4()`](https://niphr.github.io/csalert/reference/print.csfmt_ensemble_v4.md),
[`short_term_trend_v4()`](https://niphr.github.io/csalert/reference/short_term_trend_v4.md),
[`signal_detection_hlm_v4()`](https://niphr.github.io/csalert/reference/signal_detection_hlm_v4.md)

## Examples

``` r
cal <- cstime::dates_by_isoyearweek
i <- match("2023-01", cal$isoyearweek)
set.seed(1)
monday <- as.Date(cal$mon[i + rep(0:39, each = 3)])
d <- data.table::data.table(
  isoyearweek_reference = cal$isoyearweek[i + rep(0:39, each = 3)],
  reporting_date = monday + rep(c(3, 10, 17), 40),
  numerator = rpois(120, c(30, 15, 5)),
  indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
)
d <- d[reporting_date <= as.Date(cal$mon[i + 39]) + 6]
tri <- csfmt_reporting_triangle_v4(
  d,
  id_cols = c("indicator_tag", "location_code", "age", "sex")
)
ens <- nowcast_ecdf_v4(tri, max_delay_days = 21, seed = 4, n_sim = 200)
ens
#> <csfmt_ensemble_v4> full | 40 rows | 1 series | draws: numerator
```
