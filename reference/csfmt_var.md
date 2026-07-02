# Construct a csfmt measure column name from components

Construct a csfmt measure column name from components

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

  Character scalar, the measure identity (e.g. "consults_r80").

- denom:

  Optional denominator name; inserts \`\_vs\_\<denom\>\`.

- role:

  Optional statistic role:
  observed/nowcasted/forecasted/trend/baseline/status.

- q:

  Optional probability for a quantile coordinate (mutually exclusive
  with \`level\`).

- level:

  Optional status level for a \`prob\_\<level\>\` coordinate.

- per:

  Optional rate scaling (e.g. 100 -\> \`\_pr100\`).

- suffix:

  Optional unit suffix (e.g. "\_n").

## Value

Character scalar column name.

## Examples

``` r
csfmt_var("numerator", role = "nowcasted", q = 0.5)   # "numerator_nowcasted_q50x0"
#> [1] "numerator_nowcasted_q50x0"
csfmt_var("consults", denom = "population", per = 100) # a rate column name
#> [1] "consults_vs_population_pr100"
```
