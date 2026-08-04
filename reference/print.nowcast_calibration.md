# Print a \`nowcast_calibration\`

Shows the nominal interval level, the grouping, and the per-group
calibration factor table (factor \> 1 widens an under-dispersed engine;
\< 1 narrows).

## Usage

``` r
# S3 method for class 'nowcast_calibration'
print(x, ...)
```

## Arguments

- x:

  A \`nowcast_calibration\` from \[nowcast_estimate_calibration_v1\].

- ...:

  Ignored (for S3 consistency).

## Value

\`x\`, invisibly.

## See also

Neither package vignette covers calibration; see the example on
[`nowcast_estimate_calibration_v1`](https://niphr.github.io/csalert/reference/nowcast_estimate_calibration_v1.md),
which prints its result with this method.

Other nowcast calibration functions:
[`nowcast_apply_calibration_v1()`](https://niphr.github.io/csalert/reference/nowcast_apply_calibration_v1.md),
[`nowcast_estimate_calibration_v1()`](https://niphr.github.io/csalert/reference/nowcast_estimate_calibration_v1.md)
