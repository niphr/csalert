# Add a rate to a csfmt_ensemble_v4

Divides one draw matrix by another, draw by draw, and adds the result as
a new draw matrix. Column `j` is the same draw in every measure, so the
rate carries the uncertainty of both.

## Usage

``` r
ens_add_rate_v4(x, numerator, denominator, per = 100, name)
```

## Arguments

- x:

  The `csfmt_ensemble_v4`, full or compressed, that holds both measures.

- numerator, denominator:

  The names of two draw matrices in `$draws`.

- per:

  The scale of the rate. `100` gives a percentage.

- name:

  The name of the new draw matrix. It MUST be at most 63 bytes, and it
  MUST NOT end in a reserved suffix such as `_trend_gr` or `_hlm`. It
  MUST NOT be the name of a column of `$data`, such as an identity
  column or the time column. In a compressed ensemble, it MAY be the
  name of a stored measure, whose columns the rate then replaces.

## Value

`x` with the rate in `$draws[[name]]`. A draw matrix with that name is
replaced.

## Details

The method is that of
[`ens_add_rate()`](https://niphr.github.io/csalert/reference/ens_add_rate.md)
for a `csfmt_ensemble_v3`, and the rate is identical. The rate is
`per * numerator / denominator`. A zero or `NA` denominator gives `NA`,
also for `0 / 0`. The numerator is a subset of the denominator, so the
rate is capped at `per`. A draw with a numerator above its denominator
gives a warning.

On a compressed ensemble from
[`as_ensemble_v4()`](https://niphr.github.io/csalert/reference/as_ensemble_v4.md),
the function rebuilds the numerator and the denominator. Their draws are
independent, as in a full ensemble from
[`nowcast_ecdf_v4()`](https://niphr.github.io/csalert/reference/nowcast_ecdf_v4.md).
It then writes the median and the 9 percentiles of the rate to `$data`,
as
[`ens_compress_v4()`](https://niphr.github.io/csalert/reference/ens_compress_v4.md)
does.

## See also

Other v4 functions:
[`as_ensemble_v4()`](https://niphr.github.io/csalert/reference/as_ensemble_v4.md),
[`csfmt_ensemble_v4()`](https://niphr.github.io/csalert/reference/csfmt_ensemble_v4.md),
[`csfmt_reporting_triangle_v4()`](https://niphr.github.io/csalert/reference/csfmt_reporting_triangle_v4.md),
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
  isoyearweek = c("2023-01", "2023-02", "2023-03")
)
# The numerator is a subset of the denominator: positive tests out of tests.
set.seed(1)
tested <- matrix(rpois(3 * 100, 200), nrow = 3)
positive <- matrix(rbinom(length(tested), tested, 0.1), nrow = 3)
ens <- csfmt_ensemble_v4(
  d,
  id_cols = "location_code",
  draws = list(positive = positive, tested = tested)
)
ens <- ens_add_rate_v4(
  ens,
  numerator = "positive",
  denominator = "tested",
  per = 100,
  name = "positive_vs_tested_pr100"
)
names(ens$draws)
#> [1] "positive"                 "tested"                  
#> [3] "positive_vs_tested_pr100"
```
