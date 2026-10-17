# Build an ensemble from a reporting triangle with no nowcast

Returns the counts reported so far as an ensemble with one draw. Use it
for an indicator that SHOULD NOT be nowcast.

## Usage

``` r
nowcast_passthrough_v4(x, max_delay_days, denominator_col = NULL)
```

## Arguments

- x:

  The `csfmt_reporting_triangle_v4` to pass through.

- max_delay_days:

  The delay horizon in days. The totals do not depend on it.

- denominator_col:

  A denominator column to pass through in the same way. Its total also
  goes to `$data` as `<denominator_col>_observed`.

## Value

A `csfmt_ensemble_v4` with one draw per measure. `$data` holds
`original`, the observed total.

## Details

The method is that of
[`nowcast_passthrough_to_ensemble_v1()`](https://niphr.github.io/csalert/reference/nowcast_passthrough_to_ensemble_v1.md),
and the draws are identical. The draw matrix has the name of
`value_col`, with no suffix. It holds the observed total, which includes
the reports at delay `max_delay_days` or later. The function draws no
random numbers.

## See also

Other v4 functions:
[`as_ensemble_v4()`](https://niphr.github.io/csalert/reference/as_ensemble_v4.md),
[`csfmt_ensemble_v4()`](https://niphr.github.io/csalert/reference/csfmt_ensemble_v4.md),
[`csfmt_reporting_triangle_v4()`](https://niphr.github.io/csalert/reference/csfmt_reporting_triangle_v4.md),
[`ens_add_rate_v4()`](https://niphr.github.io/csalert/reference/ens_add_rate_v4.md),
[`ens_compress_v4()`](https://niphr.github.io/csalert/reference/ens_compress_v4.md),
[`mem_thresholds_v4()`](https://niphr.github.io/csalert/reference/mem_thresholds_v4.md),
[`nowcast_ecdf_v4()`](https://niphr.github.io/csalert/reference/nowcast_ecdf_v4.md),
[`print.csfmt_ensemble_v4()`](https://niphr.github.io/csalert/reference/print.csfmt_ensemble_v4.md),
[`short_term_trend_v4()`](https://niphr.github.io/csalert/reference/short_term_trend_v4.md),
[`signal_detection_hlm_v4()`](https://niphr.github.io/csalert/reference/signal_detection_hlm_v4.md)

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
tri <- csfmt_reporting_triangle_v4(
  d,
  id_cols = c("indicator_tag", "location_code", "age", "sex")
)
nowcast_passthrough_v4(tri, max_delay_days = 21)
```
