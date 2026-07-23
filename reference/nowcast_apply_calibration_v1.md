# Apply a nowcast calibration to quantile predictions

Recalibrates each quantile by scaling its distance from the median by
the learned per-group \`factor\`, so the intervals hit nominal coverage.
Groups with no learned factor (e.g. an unseen horizon) pass through
unchanged.

## Usage

``` r
nowcast_apply_calibration_v1(x, calibration)
```

## Arguments

- x:

  Long quantile predictions (\`reference\`, the calibration's \`by\`
  column(s), \`quantile_level\`, \`predicted\`) – e.g. a fresh
  \[nowcast_backtest\] output or a melted collapse.

- calibration:

  A \`nowcast_calibration\` from \[nowcast_estimate_calibration_v1\].

## Value

\`x\` with \`predicted\` recalibrated.
