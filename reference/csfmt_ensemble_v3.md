# Construct a csfmt_ensemble_v3

Construct a csfmt_ensemble_v3

## Usage

``` r
csfmt_ensemble_v3(data, id_cols, time_col = "isoyearweek", draws = list())
```

## Arguments

- data:

  data.table with the identity columns and \`time_col\`.

- id_cols:

  Character vector of identity columns defining a series.

- time_col:

  Time-ordering column (default "isoyearweek").

- draws:

  Optional named list of \`\[nrow(data) x n_draws\]\` matrices, given in
  \`data\`'s input row order (they are reordered to match the canonical
  sort).

## Value

A \`csfmt_ensemble_v3\`.
