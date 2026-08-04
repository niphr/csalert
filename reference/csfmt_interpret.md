# Interpret a dataset's columns via the naming grammar

Applies \[csfmt_parse\] to every value column (everything not in the
structural schema) and returns a catalog: one row per column with its
parsed components. This makes a dataset self-describing – generic
tooling (QC, collapse, presentation) routes on the catalog instead of
hardcoding column names.

## Usage

``` r
csfmt_interpret(d, value_cols = NULL)
```

## Arguments

- d:

  A data.table / data.frame.

- value_cols:

  Optional columns to interpret; defaults to all non-structural.

## Value

A data.table: \`column, measure, denom, role, q, level, per, suffix,
interpretable\` (the last TRUE when a role/quantile/level coordinate was
found).

## See also

Neither package vignette covers this function. It is the dataset-wide
form of
[`csfmt_parse`](https://niphr.github.io/csalert/reference/csfmt_parse.md),
and is what
[`compare_results`](https://niphr.github.io/csalert/reference/compare_results.md)
uses to find the value columns it should diff.

Other naming grammar functions:
[`csfmt_parse()`](https://niphr.github.io/csalert/reference/csfmt_parse.md),
[`csfmt_var()`](https://niphr.github.io/csalert/reference/csfmt_var.md),
[`q_label()`](https://niphr.github.io/csalert/reference/q_label.md),
[`q_value()`](https://niphr.github.io/csalert/reference/q_value.md)

## Examples

``` r
d <- data.table::data.table(
  isoyearweek = "2023-01",
  numerator_nowcasted_q50x0 = 42,
  numerator_nowcasted_vs_denominator_nowcasted_pr100_q50x0 = 8.4,
  numerator_nowcasted_status_prob_high = 0.3,
  a_column_outside_the_grammar = 1
)

# isoyearweek is structural, so it is not a value column at all; the last
# column is a value column the grammar cannot read (interpretable = FALSE)
csfmt_interpret(d)
#>                                                      column
#>                                                      <char>
#> 1:                                numerator_nowcasted_q50x0
#> 2: numerator_nowcasted_vs_denominator_nowcasted_pr100_q50x0
#> 3:                     numerator_nowcasted_status_prob_high
#> 4:                             a_column_outside_the_grammar
#>                         measure       denom      role     q  level   per suffix
#>                          <char>      <char>    <char> <num> <char> <int> <char>
#> 1:                    numerator        <NA> nowcasted   0.5   <NA>    NA   <NA>
#> 2:          numerator_nowcasted denominator nowcasted   0.5   <NA>   100   <NA>
#> 3:          numerator_nowcasted        <NA>    status    NA   high    NA   <NA>
#> 4: a_column_outside_the_grammar        <NA>      <NA>    NA   <NA>    NA   <NA>
#>    interpretable
#>           <lgcl>
#> 1:          TRUE
#> 2:          TRUE
#> 3:          TRUE
#> 4:         FALSE
```
