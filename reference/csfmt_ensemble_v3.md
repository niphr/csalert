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

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md)
is built on this format: its nowcast engine produces one and
[`ens_collapse`](https://niphr.github.io/csalert/reference/ens_collapse.md)
reduces it. The vignette never calls this constructor directly, because
the engines build the ensemble for you. Call it yourself only when you
already hold draws from somewhere else.

Other ensemble format functions:
[`print.csfmt_ensemble_v3()`](https://niphr.github.io/csalert/reference/print.csfmt_ensemble_v3.md),
[`set_time_series_id()`](https://niphr.github.io/csalert/reference/set_time_series_id.md),
[`validate_ensemble()`](https://niphr.github.io/csalert/reference/validate_ensemble.md)

## Examples

``` r
d <- data.table::data.table(
  location_code = "nation",
  age = "total",
  isoyearweek = c("2023-01", "2023-02", "2023-03")
)
set.seed(1)
ens <- csfmt_ensemble_v3(
  d,
  id_cols = c("location_code", "age"),
  draws = list(numerator_nowcasted = matrix(rpois(3 * 100, 20), nrow = 3))
)
ens
#> <csfmt_ensemble_v3> 3 rows | 1 series | draws: numerator_nowcasted

# $data carries the identity + the canonical sort keys. The trailing []
# forces the print: data.table suppresses the first auto-print of a table
# that was last modified by reference, which the constructor does.
ens$data[]
#> Key: <time_series_id, time_series_internal_id>
#>    location_code    age isoyearweek   time_series_id time_series_label
#>           <char> <char>      <char>           <char>            <char>
#> 1:        nation  total     2023-01 0ec581372be7c933   nation\037total
#> 2:        nation  total     2023-02 0ec581372be7c933   nation\037total
#> 3:        nation  total     2023-03 0ec581372be7c933   nation\037total
#>    time_series_internal_id
#>                      <int>
#> 1:                       1
#> 2:                       2
#> 3:                       3

# $draws holds one [weeks x draws] matrix per measure
dim(ens$draws$numerator_nowcasted)
#> [1]   3 100
```
