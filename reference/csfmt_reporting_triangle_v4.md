# Build a csfmt_reporting_triangle_v4

Builds the input of the v4 nowcast engines: counts by reference ISO week
and by the date each count was reported. The newest reporting date is
the as-of date.

## Usage

``` r
csfmt_reporting_triangle_v4(
  data,
  id_cols,
  reference_col = "isoyearweek_reference",
  reporting_col = "reporting_date",
  value_col = "numerator"
)
```

## Arguments

- data:

  A data.table with the identity, reference, reporting and count
  columns.

- id_cols:

  The identity columns that define one series.

- reference_col:

  The reference ISO-week column, written `"YYYY-WW"`.

- reporting_col:

  The column with the date each count was reported. Its class MUST be
  exactly `Date`, and it MUST NOT hold `NA`.

- value_col:

  The count column.

## Value

A `csfmt_reporting_triangle_v4`: a data.table with the attributes
`as_of`, a `Date`, and `id_cols`, `reference_col`, `reporting_col` and
`value_col`.

## Details

The constructor copies `data` and adds `time_series_id` and
`time_series_label`. It stops with an error when a reporting date comes
before its reference Monday, or when a count is negative.

## See also

Other v4 functions:
[`as_ensemble_v4()`](https://niphr.github.io/csalert/reference/as_ensemble_v4.md),
[`csfmt_ensemble_v4()`](https://niphr.github.io/csalert/reference/csfmt_ensemble_v4.md),
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
attr(tri, "as_of")
#> [1] "2023-10-05"
```
