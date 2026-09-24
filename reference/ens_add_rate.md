# Add a rate to an ensemble

Divides one draw matrix by another, draw by draw, and adds the result as
a new draw matrix. Column `j` is the same draw in every measure, so the
rate carries the uncertainty of both.

## Usage

``` r
ens_add_rate(x, ...)

# S3 method for class 'csfmt_ensemble_v3'
ens_add_rate(x, numerator, denominator, per = 100, name = NULL, ...)
```

## Arguments

- x:

  The `csfmt_ensemble_v3` that holds both measures.

- ...:

  Passed to the method.

- numerator, denominator:

  Two draw matrices in `$draws`.

- per:

  The scale of the rate. `100` gives a percentage.

- name:

  The name of the new measure. `NULL` uses
  `csfmt_var(numerator, denom = denominator, per = per)`.

## Value

`x` with the rate in `$draws`.

## Details

A zero denominator gives `NA`, not 0. The rate is capped at `per`,
because the numerator is a subset of the denominator, and a draw above
the cap gives a warning.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
stage 4.

Other ensemble operations:
[`ens_collapse()`](https://niphr.github.io/csalert/reference/ens_collapse.md),
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
# The numerator is a SUBSET of the denominator: positive tests out of tests
# taken. So simulate the denominator first, and the numerator from it.
set.seed(1)
denom <- matrix(rpois(3 * 100, 200), nrow = 3)
numer <- matrix(rbinom(length(denom), size = denom, prob = 0.10), nrow = 3)
ens <- csfmt_ensemble_v3(
  d,
  id_cols = c("location_code", "age"),
  draws = list(
    numerator_nowcasted = numer,
    denominator_nowcasted = denom
  )
)

ens <- ens_add_rate(
  ens,
  numerator = "numerator_nowcasted",
  denominator = "denominator_nowcasted",
  per = 100
)

# the rate is a third draw matrix, named by the grammar
names(ens$draws)
#> [1] "numerator_nowcasted"                               
#> [2] "denominator_nowcasted"                             
#> [3] "numerator_nowcasted_vs_denominator_nowcasted_pr100"

# its interval carries the uncertainty of both measures
r <- ens_collapse(ens, probs = c(0.05, 0.5, 0.95))
r[, .(
  isoyearweek,
  lo = numerator_nowcasted_vs_denominator_nowcasted_pr100_q05x0,
  med = numerator_nowcasted_vs_denominator_nowcasted_pr100_q50x0,
  hi = numerator_nowcasted_vs_denominator_nowcasted_pr100_q95x0
)]
#>    isoyearweek       lo      med       hi
#>         <char>    <num>    <num>    <num>
#> 1:     2023-01 7.115385 9.755516 14.31502
#> 2:     2023-02 5.699153 9.867335 13.52267
#> 3:     2023-03 6.371382 9.476179 13.27110
```
