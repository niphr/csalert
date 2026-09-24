# Split every value column name of a table into its parts

Runs
[`csfmt_parse()`](https://niphr.github.io/csalert/reference/csfmt_parse.md)
on every value column, and returns one row per column. Code can then
find a column by its parts.

## Usage

``` r
csfmt_interpret(d, value_cols = NULL)
```

## Arguments

- d:

  A data.table or data.frame.

- value_cols:

  The columns to read. `NULL` reads every value column.

## Value

A data.table with the columns `column`, `measure`, `denom`, `role`, `q`,
`level`, `per`, `suffix` and `interpretable`. `interpretable` is `TRUE`
when the name has a role, a quantile label or a level.

## Details

A value column is any column outside a fixed list of 23 structural
names. The list includes `location_code`, `age`, `sex`, `isoyearweek`,
`indicator_tag`, `original` and the `time_series_*` columns.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
whose naming-grammar section shows the grammar.
[`compare_results()`](https://niphr.github.io/csalert/reference/compare_results.md)
uses this function.

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

# isoyearweek is structural, so it has no row. The last column is a value
# column that the grammar cannot read, so its interpretable is FALSE.
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
