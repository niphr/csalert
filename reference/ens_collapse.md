# Collapse the draws of an ensemble to quantiles

Reduces every draw matrix to quantile columns, and drops the draws. It
is the last stage: no stage takes a collapsed table as input.

## Usage

``` r
ens_collapse(x, ...)

# S3 method for class 'csfmt_ensemble_v3'
ens_collapse(
  x,
  probs = c(0.025, 0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 0.95, 0.975),
  heal = FALSE,
  ...
)
```

## Arguments

- x:

  The `csfmt_ensemble_v3` to collapse.

- ...:

  Passed to the method.

- probs:

  The probabilities of the quantile columns.

- heal:

  If `TRUE`, return a `csfmt_rts_data_v3` from
  [`cstidy::set_csfmt_rts_data_v3()`](https://niphr.github.io/cstidy/reference/set_csfmt_rts_data_v3.html),
  which adds the calendar columns.

## Value

A copy of `$data` with a `<measure>_<q-label>` column for each measure
and probability. It is a data.table, or a `csfmt_rts_data_v3` when
`heal = TRUE`.

## Details

A status matrix, one with a `levels` attribute, also gives a
`<measure>_prob_<level>` column per level, with the share of draws at
that level. Its quantile columns hold the code of the lowest level whose
cumulative share reaches the probability. Both ignore `NA` draws.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
stage 8.

Other ensemble operations:
[`ens_add_rate()`](https://niphr.github.io/csalert/reference/ens_add_rate.md),
[`mem_thresholds_v1()`](https://niphr.github.io/csalert/reference/mem_thresholds_v1.md),
[`short_term_trend()`](https://niphr.github.io/csalert/reference/short_term_trend.md),
[`signal_detection_hlm()`](https://niphr.github.io/csalert/reference/signal_detection_hlm.md)

## Examples

``` r
d <- data.table::data.table(
  location_code = "nation",
  age = "total",
  isoyearweek = c("2023-01", "2023-02", "2023-03")
)
set.seed(1)
ens <- csfmt_ensemble_v3(
  d,
  id_cols = c("location_code", "age"),
  draws = list(numerator_nowcasted = matrix(rpois(3 * 100, 20), nrow = 3))
)

# one column per probability, named by the naming grammar
r <- ens_collapse(ens, probs = c(0.05, 0.5, 0.95))
r[, .(
  isoyearweek,
  lo = numerator_nowcasted_q05x0,
  med = numerator_nowcasted_q50x0,
  hi = numerator_nowcasted_q95x0
)]
#>    isoyearweek    lo   med    hi
#>         <char> <num> <num> <num>
#> 1:     2023-01    13    19 27.00
#> 2:     2023-02    13    19 28.05
#> 3:     2023-03    12    19 27.00

# the quantile columns are all that the collapse adds, and the draws are gone
setdiff(names(r), names(ens$data))
#> [1] "numerator_nowcasted_q05x0" "numerator_nowcasted_q50x0"
#> [3] "numerator_nowcasted_q95x0"
```
