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
