# Compress a csfmt_ensemble_v4 into a table to store

Returns `$data` of `x` as a data.table, with the median and 9
percentiles of each base measure in place of its draws.
[`as_ensemble_v4()`](https://niphr.github.io/csalert/reference/as_ensemble_v4.md)
turns the table back into an ensemble.

## Usage

``` r
ens_compress_v4(x)
```

## Arguments

- x:

  A `csfmt_ensemble_v4`, full or compressed. Each column of `$data` MUST
  be an atomic vector that is not a factor.

## Value

A data.table with the columns of `x$data` and the columns of each base
measure. Each column name MUST be at most 63 bytes, and the function
stops with an error when one is not.

## Details

A base measure is a draw matrix whose name does not end in a reserved
suffix, such as `_trend_beta1` or `_hlm`. Each base measure `<m>`
becomes these columns:

- `<m>`: the median of the draws.

- `<m>_q02x5` to `<m>_q97x5`: the draws at the 9 percentiles 2.5, 5, 10,
  25, 50, 75, 90, 95 and 97.5.

The percentiles are `NA` in a row where every draw that is not `NA` has
the same value. A row with one draw, as from
[`nowcast_passthrough_v4()`](https://niphr.github.io/csalert/reference/nowcast_passthrough_v4.md),
is such a row. The table does not hold the derived draw matrices. The
columns that the steps wrote to `$data` already summarise them.

The function draws no random numbers.

## See also

Other v4 functions:
[`as_ensemble_v4()`](https://niphr.github.io/csalert/reference/as_ensemble_v4.md),
[`csfmt_ensemble_v4()`](https://niphr.github.io/csalert/reference/csfmt_ensemble_v4.md),
[`csfmt_reporting_triangle_v4()`](https://niphr.github.io/csalert/reference/csfmt_reporting_triangle_v4.md),
[`ens_add_rate_v4()`](https://niphr.github.io/csalert/reference/ens_add_rate_v4.md),
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
  isoyearweek = sprintf("2023-%02d", 1:10)
)
set.seed(1)
ens <- csfmt_ensemble_v4(
  d,
  id_cols = "location_code",
  draws = list(cases = matrix(rpois(10 * 200, 20), nrow = 10))
)
stored <- ens_compress_v4(ens)
stored[, .(isoyearweek, cases, cases_q02x5, cases_q97x5)]
#>     isoyearweek cases cases_q02x5 cases_q97x5
#>          <char> <num>       <num>       <num>
#>  1:     2023-01    20      11.975      29.000
#>  2:     2023-02    20      11.000      29.000
#>  3:     2023-03    20      12.000      29.000
#>  4:     2023-04    19      11.000      29.025
#>  5:     2023-05    19      11.975      29.000
#>  6:     2023-06    20      11.975      29.025
#>  7:     2023-07    20      11.975      27.025
#>  8:     2023-08    19      12.975      28.000
#>  9:     2023-09    20      11.000      29.000
#> 10:     2023-10    19      12.000      29.025
```
