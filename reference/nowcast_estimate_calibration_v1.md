# Estimate a nowcast calibration from a backtest

Learns a per-group interval-scaling correction (conformal) from past
nowcasts scored against settled truth. See
\[nowcast_apply_calibration_v1\] to use it.

## Usage

``` r
nowcast_estimate_calibration_v1(backtest, truth, level = 0.9, by = "horizon")
```

## Arguments

- backtest:

  Long quantile nowcasts (from \[nowcast_backtest\]): \`reference\`, the
  \`by\` column(s), \`quantile_level\`, \`predicted\`.

- truth:

  Settled totals (from \[nowcast_truth\]): \`reference\`, \`truth\`.

- level:

  Central interval level to calibrate on (default 0.9).

- by:

  Grouping column(s) the factor varies over (default "horizon").

## Value

A \`nowcast_calibration\`: per-group raw coverage + scale \`factor\`.
