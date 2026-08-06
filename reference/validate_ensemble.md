# Check a csfmt_ensemble_v3's structural shape

Checks the shape of an ensemble, and only the shape. It verifies the
class, that \`\$data\` is a data.table and \`\$draws\` a list, that
\`\$data\` has the \`time_series_id\` and \`time_series_internal_id\`
columns, and that every entry of \`\$draws\` is a matrix with one row
per row of \`\$data\`.

## Usage

``` r
validate_ensemble(ens)
```

## Arguments

- ens:

  A \`csfmt_ensemble_v3\`.

## Value

\`ens\` invisibly; errors on a violation of the shape checks above.

## What it does NOT check

The constructor \[csfmt_ensemble_v3\] establishes more than this
function verifies. It does NOT check the sort order or the key. It also
does NOT check:

- that \`time_series_internal_id\` is a dense 1..n within each series;

- that \`time_series_label\` is present;

- that a draw matrix's rows still correspond to the same weeks as
  \`\$data\`.

Only the row COUNT is compared, so permuting the rows of \`\$data\` or
of a draw matrix passes.

So this is not a safety net for hand-edited objects. If you have edited
\`\$data\` or \`\$draws\` yourself, rebuild with \[csfmt_ensemble_v3\]
rather than relying on this check.

## See also

Neither package vignette covers this function. \[csfmt_ensemble_v3\] and
every ensemble stage call it on the way out, so you rarely call it
yourself.

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

# returns invisibly when the shape checks pass
validate_ensemble(ens)

# a draw matrix with the wrong number of rows is caught
bad <- ens
bad$draws$numerator_nowcasted <- matrix(1, nrow = 2, ncol = 4)
try(validate_ensemble(bad))
#> Error in validate_ensemble(bad) : 
#>   draws[['numerator_nowcasted']] has 2 rows; expected 3 (nrow($data))

# but a draw matrix whose rows have been PERMUTED has the right count, so it
# passes -- the row-to-week correspondence is not checked
scrambled <- ens
scrambled$draws$numerator_nowcasted <-
  ens$draws$numerator_nowcasted[c(2, 3, 1), , drop = FALSE]
validate_ensemble(scrambled)
"passed, although the draws no longer line up with $data"
#> [1] "passed, although the draws no longer line up with $data"
```
