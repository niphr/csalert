# Rebuild a csfmt_ensemble_v4 from a stored table

Turns a table from
[`ens_compress_v4()`](https://niphr.github.io/csalert/reference/ens_compress_v4.md)
into a compressed `csfmt_ensemble_v4`. The v4 steps take it as they take
a full ensemble, and rebuild the draws of each base measure that they
read.

## Usage

``` r
as_ensemble_v4(d, id_cols, time_col = "isoyearweek", n_sim = 1000L)
```

## Arguments

- d:

  The table from
  [`ens_compress_v4()`](https://niphr.github.io/csalert/reference/ens_compress_v4.md),
  as a data.table or a data.frame. A DBI read returns a data.frame. The
  function converts a copy, so the object of the caller does not change.

- id_cols:

  The identity columns that define one series.

- time_col:

  The column that orders time within a series.

- n_sim:

  The number of draws in each rebuilt draw matrix.

## Value

A `csfmt_ensemble_v4` with `state` `"compressed"`. Its `$draws` is
empty, and it holds only the draw matrices that the steps add.

## Details

A base measure is a column `<m>` that has the 9 percentile columns
`<m>_q02x5` to `<m>_q97x5`, where `<m>` does not end in a reserved
suffix. The table holds no other metadata, so a table with every
attribute removed gives the same ensemble.

The rebuild draws one u from U(0, 1) per row and draw, with seed 4, and
then puts back the random-number state of the caller. Every base measure
of a row uses that u, and the weeks of a series get independent u. The
value of a draw is u through the quantile function of the row. That
function interpolates linearly between the 9 stored percentiles, and it
is flat below 2.5% and above 97.5%. A row with `NA` percentiles gets its
point value in every draw.

A rate rebuilt from its own percentiles loses the pairing of its draws
with the draws of its numerator and denominator. Before a step on a
rate, you MUST add the rate again from its parts with
[`ens_add_rate_v4()`](https://niphr.github.io/csalert/reference/ens_add_rate_v4.md).
The step then reads the recomputed rate.

## See also

Other v4 functions:
[`csfmt_ensemble_v4()`](https://niphr.github.io/csalert/reference/csfmt_ensemble_v4.md),
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
  isoyearweek = sprintf("2023-%02d", 1:10)
)
set.seed(1)
ens <- csfmt_ensemble_v4(
  d,
  id_cols = "location_code",
  draws = list(cases = matrix(rpois(10 * 200, 20 * exp(0.1 * 1:10)), 10))
)
stored <- ens_compress_v4(ens)
back <- as_ensemble_v4(stored, id_cols = "location_code")
back
#> <csfmt_ensemble_v4> compressed | 10 rows | 1 series | draws: none
back <- short_term_trend_v4(back, measure = "cases", width = 5, seed = 4)
back$data[, .(isoyearweek, cases, cases_trend_pinc)]
#>     isoyearweek cases cases_trend_pinc
#>          <char> <num>            <num>
#>  1:     2023-01    21               NA
#>  2:     2023-02    25               NA
#>  3:     2023-03    26               NA
#>  4:     2023-04    29               NA
#>  5:     2023-05    32        0.8505280
#>  6:     2023-06    36        0.8591968
#>  7:     2023-07    40        0.8905054
#>  8:     2023-08    43        0.8755587
#>  9:     2023-09    49        0.8978004
#> 10:     2023-10    54        0.9023639
```
