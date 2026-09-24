# Build a measure column name from its parts

Joins the parts in the order
`<measure>[_vs_<denom>][_<role>][_<q-label> | _prob_<level>][_pr<per>][<suffix>]`.
The pipeline names its draw matrices and quantile columns with it, so
build a name with it before you look a column up.

## Usage

``` r
csfmt_var(
  measure,
  denom = NULL,
  role = NULL,
  q = NULL,
  level = NULL,
  per = NULL,
  suffix = NULL
)
```

## Arguments

- measure:

  The name of the measure, for example `"consults_r80"`.

- denom:

  A denominator. It adds `_vs_<denom>`.

- role:

  A role, for example `"nowcasted"`, `"trend"` or `"status"`. It adds
  `_<role>`.

- q:

  A probability. It adds the label from
  [`q_label()`](https://niphr.github.io/csalert/reference/q_label.md).
  Give `q` or `level`, not both.

- level:

  A status level. It adds `_prob_<level>`.

- per:

  A rate scale. `100` adds `_pr100`.

- suffix:

  A unit suffix, added as written, for example `"_n"`.

## Value

The column name.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
whose naming-grammar section builds and parses a name.

Other naming grammar functions:
[`csfmt_interpret()`](https://niphr.github.io/csalert/reference/csfmt_interpret.md),
[`csfmt_parse()`](https://niphr.github.io/csalert/reference/csfmt_parse.md),
[`q_label()`](https://niphr.github.io/csalert/reference/q_label.md),
[`q_value()`](https://niphr.github.io/csalert/reference/q_value.md)

## Examples

``` r
csfmt_var("numerator", role = "nowcasted", q = 0.5)   # "numerator_nowcasted_q50x0"
#> [1] "numerator_nowcasted_q50x0"
csfmt_var("consults", denom = "population", per = 100) # a rate column name
#> [1] "consults_vs_population_pr100"
```
