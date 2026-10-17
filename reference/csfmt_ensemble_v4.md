# Build a csfmt_ensemble_v4

Builds the ensemble that the v4 methods take and return. It holds one
row per series and week in `$data`, and one draw matrix per measure in
`$draws`.

## Usage

``` r
csfmt_ensemble_v4(data, id_cols, time_col = "isoyearweek", draws = list())
```

## Arguments

- data:

  A data.table with the identity columns and `time_col`.

- id_cols:

  The identity columns that define one series.

- time_col:

  The column that orders time within a series.

- draws:

  A named list of matrices, one per measure, with `nrow(data)` rows in
  the row order of `data`.

## Value

A `csfmt_ensemble_v4`: a list with `data`, `draws`, `id_cols`,
`time_col` and `state`. The `state` is `"full"`, which means that
`$draws` holds the draws.

## Details

The constructor copies `data` and adds `time_series_id` and
`time_series_label`. It sorts the rows by series and `time_col`, adds
`time_series_internal_id`, `1..n` within each series, and puts the draw
rows in the same order. The names of the columns and of the draw
matrices MUST be at most 63 bytes, and MUST differ in their first 63
bytes.

## See also

Other v4 functions:
[`as_ensemble_v4()`](https://niphr.github.io/csalert/reference/as_ensemble_v4.md),
[`csfmt_reporting_triangle_v4()`](https://niphr.github.io/csalert/reference/csfmt_reporting_triangle_v4.md),
[`ens_add_rate_v4()`](https://niphr.github.io/csalert/reference/ens_add_rate_v4.md),
[`ens_compress_v4()`](https://niphr.github.io/csalert/reference/ens_compress_v4.md),
[`mem_thresholds_v4()`](https://niphr.github.io/csalert/reference/mem_thresholds_v4.md),
[`nowcast_ecdf_v4()`](https://niphr.github.io/csalert/reference/nowcast_ecdf_v4.md),
[`nowcast_passthrough_v4()`](https://niphr.github.io/csalert/reference/nowcast_passthrough_v4.md),
[`print.csfmt_ensemble_v4()`](https://niphr.github.io/csalert/reference/print.csfmt_ensemble_v4.md),
[`short_term_trend_v4()`](https://niphr.github.io/csalert/reference/short_term_trend_v4.md),
[`signal_detection_hlm_v4()`](https://niphr.github.io/csalert/reference/signal_detection_hlm_v4.md)

## Examples

``` r
d <- data.table::data.table(
  location_code = "nation",
  age = "total",
  isoyearweek = c("2023-01", "2023-02", "2023-03")
)
set.seed(1)
ens <- csfmt_ensemble_v4(
  d,
  id_cols = c("location_code", "age"),
  draws = list(numerator = matrix(rpois(3 * 100, 20), nrow = 3))
)
ens
#> <csfmt_ensemble_v4> full | 3 rows | 1 series | draws: numerator
ens$state
#> [1] "full"
```
