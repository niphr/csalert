# Print a \`csfmt_ensemble_v3\`

Compact one-line summary: number of rows, number of time series, and the
names of the per-measure draw matrices.

## Usage

``` r
# S3 method for class 'csfmt_ensemble_v3'
print(x, ...)
```

## Arguments

- x:

  A \`csfmt_ensemble_v3\`.

- ...:

  Ignored (for S3 consistency).

## Value

\`x\`, invisibly.

## See also

[`vignette("nowcasting", package = "csalert")`](https://niphr.github.io/csalert/articles/nowcasting.md),
which prints an ensemble with this method right after the nowcast step.

Other ensemble format functions:
[`csfmt_ensemble_v3()`](https://niphr.github.io/csalert/reference/csfmt_ensemble_v3.md),
[`set_time_series_id()`](https://niphr.github.io/csalert/reference/set_time_series_id.md),
[`validate_ensemble()`](https://niphr.github.io/csalert/reference/validate_ensemble.md)
