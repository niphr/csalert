# Build a csfmt_ensemble_v3

Builds the working format of the pipeline. `$data` is a data.table with
one row per series and week. `$draws` holds one matrix per measure, with
one row per row of `$data` and one column per draw.

## Usage

``` r
csfmt_ensemble_v3(data, id_cols, time_col = "isoyearweek", draws = list())
```

## Arguments

- data:

  A data.table with the identity columns and `time_col`.

- id_cols:

  The identity columns that define one series.

- time_col:

  The column that orders time within a series.

- draws:

  A named list of matrices, one per measure, with `nrow(data)` rows in
  the row order of `data`.

## Value

A `csfmt_ensemble_v3`.

## Details

The constructor copies `data`, adds the ids of
[`set_time_series_id()`](https://niphr.github.io/csalert/reference/set_time_series_id.md),
and sorts the rows by series and `time_col`. It adds
`time_series_internal_id`, `1..n` within each series, and puts the draw
rows in the same order. The nowcast engines call it for you.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
which builds an ensemble with a nowcast engine.

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

# $data holds the identity columns and the sort keys. The trailing [] makes
# data.table print a table that was last changed by reference.
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

# $draws holds one matrix per measure, with rows = weeks, columns = draws
dim(ens$draws$numerator_nowcasted)
#> [1]   3 100
```
