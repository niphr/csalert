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
