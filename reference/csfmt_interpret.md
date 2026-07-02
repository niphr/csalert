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
