# Assign content-hash time_series_id (+ readable label) by reference

Assign content-hash time_series_id (+ readable label) by reference

## Usage

``` r
set_time_series_id(d, id_cols, sep = "\037")
```

## Arguments

- d:

  data.table.

- id_cols:

  Character vector of identity columns defining a series.

- sep:

  Separator for the canonical key (default unit-separator).

## Value

\`d\`, modified by reference (invisibly).

## See also

Neither package vignette covers this function. It is called for you by
[`csfmt_ensemble_v3`](https://niphr.github.io/csalert/reference/csfmt_ensemble_v3.md)
and
[`csfmt_reporting_triangle_v3`](https://niphr.github.io/csalert/reference/csfmt_reporting_triangle_v3.md);
call it directly only when you are keying a data.table those
constructors never see.

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

# the two nation rows share one content hash; the county row gets its own
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
