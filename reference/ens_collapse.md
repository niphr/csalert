# Collapse a csfmt_ensemble_v3 to a quantile-summary

An ensemble operation (\`ens\_\` family): dispatches on the ensemble
class, matching \[nowcast_quasipoisson_v1()\] / \[short_term_trend()\].

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

  A \`csfmt_ensemble_v3\`.

- ...:

  Passed to methods.

- probs:

  Numeric vector of probabilities for the quantile columns.

- heal:

  If TRUE, heal the result into a \`cstidy::csfmt_rts_data_v3\` (the
  clean weekly csfmt) instead of returning a plain data.table.

## Value

A \`data.table\` (or \`csfmt_rts_data_v3\` if \`heal=TRUE\`): \`\$data\`
plus \`\<measure\>\_qNNxN\` columns for every measure in \`\$draws\`; no
draws.

## See also

[`vignette("nowcasting", package = "csalert")`](https://niphr.github.io/csalert/articles/nowcasting.md),
which collapses a nowcast ensemble with this function and plots the
resulting band.

Other ensemble operations:
[`ens_add_rate()`](https://niphr.github.io/csalert/reference/ens_add_rate.md)

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

# one column per requested probability, named by the grammar
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

# the quantile columns are all that collapse adds; the draws are gone, and
# this reduction is one-way
setdiff(names(r), names(ens$data))
#> [1] "numerator_nowcasted_q05x0" "numerator_nowcasted_q50x0"
#> [3] "numerator_nowcasted_q95x0"
```
