# Check the shape of a csfmt_ensemble_v3

Checks the class, and that `$data` is a data.table with `time_series_id`
and `time_series_internal_id`. Checks that each entry of `$draws` is a
matrix with one row per row of `$data`. Every ensemble stage calls it.

## Usage

``` r
validate_ensemble(ens)
```

## Arguments

- ens:

  The `csfmt_ensemble_v3` to check.

## Value

`ens`, invisibly. A failed check is an error.

## What it does NOT check

It does NOT check:

- the sort order or the key of `$data`,

- that `time_series_internal_id` counts `1..n` in each series,

- that `time_series_label` exists.

It compares only the number of rows, so a draw matrix with its rows in
the wrong order passes. If you edit `$data` or `$draws` yourself,
rebuild the object with
[`csfmt_ensemble_v3()`](https://niphr.github.io/csalert/reference/csfmt_ensemble_v3.md).

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
which shows the ensemble format.

Other ensemble format functions:
[`csfmt_ensemble_v3()`](https://niphr.github.io/csalert/reference/csfmt_ensemble_v3.md),
[`print.csfmt_ensemble_v3()`](https://niphr.github.io/csalert/reference/print.csfmt_ensemble_v3.md),
[`set_time_series_id()`](https://niphr.github.io/csalert/reference/set_time_series_id.md)

## Examples

``` r
d <- data.table::data.table(
  location_code = "nation",
  age = "total",
  isoyearweek = c("2023-01", "2023-02", "2023-03")
)
ens <- csfmt_ensemble_v3(
  d,
  id_cols = c("location_code", "age"),
  draws = list(numerator_nowcasted = matrix(1:12, nrow = 3))
)

# returns invisibly when the checks pass
validate_ensemble(ens)

# a draw matrix with the wrong number of rows is an error
bad <- ens
bad$draws$numerator_nowcasted <- matrix(1, nrow = 2, ncol = 4)
try(validate_ensemble(bad))
#> Error : draws[['numerator_nowcasted']] has 2 rows; expected 3 (nrow($data))

# a draw matrix with PERMUTED rows has the right count, so it passes
scrambled <- ens
scrambled$draws$numerator_nowcasted <-
  ens$draws$numerator_nowcasted[c(2, 3, 1), , drop = FALSE]
validate_ensemble(scrambled)
"passed, although the draws no longer line up with $data"
#> [1] "passed, although the draws no longer line up with $data"
```
