# Add a rate measure to an ensemble

An ensemble operation (\`ens\_\` family): dispatches on the ensemble
class, so the class – not a name prefix on the caller – carries the
"operates on an ensemble" meaning, matching
\[nowcast_quasipoisson_v1()\] / \[short_term_trend()\].

## Usage

``` r
ens_add_rate(x, ...)

# S3 method for class 'csfmt_ensemble_v3'
ens_add_rate(x, numerator, denominator, per = 100, name = NULL, ...)
```

## Arguments

- x:

  A \`csfmt_ensemble_v3\`.

- ...:

  Passed to methods.

- numerator, denominator:

  Measure names present in \`\$draws\`.

- per:

  Scaling factor (e.g. 100 for percent).

- name:

  Optional output measure name (defaults to the grammar name).

## Value

\`x\` with the rate measure added to \`\$draws\`.

## See also

[`vignette("nowcasting", package = "csalert")`](https://niphr.github.io/csalert/articles/nowcasting.md)
names this function in its closing "Where next" list but does not
demonstrate it; the example below is its only worked demonstration.

Other ensemble operations:
[`ens_collapse()`](https://niphr.github.io/csalert/reference/ens_collapse.md)

## Examples

``` r
d <- data.table::data.table(
  location_code = "nation",
  age = "total",
  isoyearweek = c("2023-01", "2023-02", "2023-03")
)
# The numerator must be a SUBSET of the denominator (tests positive out of
# tests taken), so simulate the denominator first and the numerator
# conditionally on it. Two independent Poissons would not be a proportion.
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
