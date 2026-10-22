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

The rebuild draws one u from U(0, 1) per row and draw for each base
measure. It then puts back the random-number state of the caller. The
seed of a measure comes from its name and seed 4, so it does not depend
on the order of the rebuilds. Two measures, and two weeks of a series,
get independent u, as the numerator and the denominator of
[`nowcast_ecdf_v4()`](https://niphr.github.io/csalert/reference/nowcast_ecdf_v4.md)
are independent. The value of a draw is u through the quantile function
of the row. That function passes through the 9 stored percentiles, and
it is flat below 2.5% and above 97.5%. A row with `NA` percentiles gets
its point value in every draw.

Between two stored percentiles, a row whose 9 percentiles are all 0 or
more is interpolated linearly on the
[`log1p()`](https://rdrr.io/r/base/Log.html) scale. A row with a
negative percentile is interpolated linearly. Counts and rates are
right-skewed, and a straight line on their own scale puts too many draws
in the upper tail. On a replay of luftvei data, with 24 indicators and
53 as-of dates, this rule raised the agreement of HLM P(high) with the
full draws. In the 1,272 newest weeks, it was within 0.05 in 95.0%,
against 92.3% with the straight line. At the older horizons it was 100%
with both rules.

A rate rebuilt from its own percentiles keeps the stored distribution of
the rate. A rate added again from its rebuilt parts with
[`ens_add_rate_v4()`](https://niphr.github.io/csalert/reference/ens_add_rate_v4.md)
is the ratio of independent draws, as in a full ensemble from
[`nowcast_ecdf_v4()`](https://niphr.github.io/csalert/reference/nowcast_ecdf_v4.md).

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
#>  5:     2023-05    32        0.8385204
#>  6:     2023-06    36        0.8538473
#>  7:     2023-07    40        0.8916200
#>  8:     2023-08    43        0.8853527
#>  9:     2023-09    49        0.8993051
#> 10:     2023-10    54        0.8989642
```
