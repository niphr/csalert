# Build an ensemble from a reporting triangle WITHOUT nowcasting (passthrough)

Collapse the triangle to the observed (reported-so-far) totals per
reference week and wrap them as a degenerate single-draw ensemble. An
indicator that should NOT be nowcast-completed (because reporting is
effectively complete, or the analyst has chosen not to model the delay)
then flows through the SAME rate/trend/MEM/collapse pipeline with its
observed values unchanged. It emits the same \`\<measure\>\_nowcasted\`
columns as the modelling engines – here equal to the observed value – so
all downstream code is identical; the single draw makes every collapsed
quantile equal the observed point.

## Usage

``` r
nowcast_passthrough_to_ensemble_v1(x, max_delay, denominator_col = NULL)
```

## Arguments

- x:

  A \`csfmt_reporting_triangle_v3\`.

- max_delay:

  Delay horizon (defines the contiguous reference grid).

- denominator_col:

  Optional denominator column, carried through the same way (its
  observed total is also surfaced as \`\<denom\>\_observed\`).

## Value

A \`csfmt_ensemble_v3\` with single-column draw matrices.
