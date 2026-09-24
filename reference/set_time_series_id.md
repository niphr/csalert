# Add a content-hash series id to a data.table

Adds `time_series_label`, the identity values joined by `sep`, and
`time_series_id`, the xxhash64 digest of that label. The id depends only
on the identity values, so a series gets the same id in every table.

## Usage

``` r
set_time_series_id(d, id_cols, sep = "\037")
```

## Arguments

- d:

  A data.table. The function changes it by reference.

- id_cols:

  The identity columns that define one series.

- sep:

  The separator in the label. The default is the ASCII unit separator,
  `"\037"`.

## Value

`d`, invisibly.

## Details

[`csfmt_ensemble_v3()`](https://niphr.github.io/csalert/reference/csfmt_ensemble_v3.md)
and
[`csfmt_reporting_triangle_v3()`](https://niphr.github.io/csalert/reference/csfmt_reporting_triangle_v3.md)
call this function for you.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
which shows the ensemble format.

Other ensemble format functions:
[`csfmt_ensemble_v3()`](https://niphr.github.io/csalert/reference/csfmt_ensemble_v3.md),
[`print.csfmt_ensemble_v3()`](https://niphr.github.io/csalert/reference/print.csfmt_ensemble_v3.md),
[`validate_ensemble()`](https://niphr.github.io/csalert/reference/validate_ensemble.md)

## Examples

``` r
d <- data.table::data.table(
  location_code = c("nation", "nation", "county03"),
  age = "total",
  isoyearweek = c("2023-01", "2023-02", "2023-01"),
  numerator = c(10, 12, 4)
)
set_time_series_id(d, id_cols = c("location_code", "age"))

# the two nation rows share one id, and the county row has its own
d[]
#>    location_code    age isoyearweek numerator   time_series_id
#>           <char> <char>      <char>     <num>           <char>
#> 1:        nation  total     2023-01        10 0ec581372be7c933
#> 2:        nation  total     2023-02        12 0ec581372be7c933
#> 3:      county03  total     2023-01         4 0d06fc1a57d1a2a5
#>    time_series_label
#>               <char>
#> 1:   nation\037total
#> 2:   nation\037total
#> 3: county03\037total
```
