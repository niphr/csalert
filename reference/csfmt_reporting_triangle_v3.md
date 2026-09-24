# Build a csfmt_reporting_triangle_v3

Builds the input of the nowcast engines: counts by reference ISO week
and by the date each count was reported. The newest reporting date is
the as-of boundary.

## Usage

``` r
csfmt_reporting_triangle_v3(
  data,
  id_cols,
  reference_col = "isoyearweek_reference",
  reporting_col = "reporting_date",
  value_col = "numerator"
)
```

## Arguments

- data:

  A data.table with the identity, reference, reporting and count
  columns.

- id_cols:

  The identity columns that define one series.

- reference_col:

  The reference ISO-week column, written `"YYYY-WW"`.

- reporting_col:

  The column with the date each count was reported. Its class MUST be
  exactly `Date`, so an `IDate` is an error. It MUST NOT hold `NA`. One
  `NA` would make the as-of boundary `NA`. Every nowcast engine would
  then return the observed totals with no warning.

- value_col:

  The count column.

## Value

A `csfmt_reporting_triangle_v3`: a data.table with the attributes
`as_of`, a `Date`, and `id_cols`, `reference_col`, `reporting_col` and
`value_col`.

## Details

The triangle is sparse. An absent cell on or before the as-of date is a
zero, and a cell after it is not reported yet. The constructor copies
`data` and adds the ids of
[`set_time_series_id()`](https://niphr.github.io/csalert/reference/set_time_series_id.md).
It stops with an error when a reporting date comes before its reference
Monday, or a count is negative.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
which takes a triangle through the whole pipeline.

Other reporting triangle functions:
[`isoyearweek_week_start()`](https://niphr.github.io/csalert/reference/isoyearweek_week_start.md),
[`reporting_triangle_matrix()`](https://niphr.github.io/csalert/reference/reporting_triangle_matrix.md)

## Examples

``` r
# 40 reference weeks, each reported 3, 10 and 17 days after its Monday. The
# data stops at one as-of date, so the newest weeks are still incomplete.
cal <- cstime::dates_by_isoyearweek
i <- match("2023-01", cal$isoyearweek)
set.seed(1)
monday <- as.Date(cal$mon[i + rep(0:39, each = 3)])
d <- data.table::data.table(
  isoyearweek_reference = cal$isoyearweek[i + rep(0:39, each = 3)],
  reporting_date = monday + rep(c(3, 10, 17), 40),
  numerator = rpois(120, c(30, 15, 5)),
  indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
)
d <- d[reporting_date <= as.Date(cal$mon[i + 39]) + 6]

tri <- csfmt_reporting_triangle_v3(
  d,
  id_cols = c("indicator_tag", "location_code", "age", "sex")
)

# the as-of boundary is the newest reporting date in the data
attr(tri, "as_of")
#> [1] "2023-10-05"
head(tri, 3)
#>    isoyearweek_reference reporting_date numerator indicator_tag location_code
#>                   <char>         <Date>     <int>        <char>        <char>
#> 1:               2023-01     2023-01-05        26             x        nation
#> 2:               2023-01     2023-01-12        20             x        nation
#> 3:               2023-01     2023-01-19         8             x        nation
#>       age    sex   time_series_id             time_series_label
#>    <char> <char>           <char>                        <char>
#> 1:  total  total d8da72e3fbb5fd29 x\037nation\037total\037total
#> 2:  total  total d8da72e3fbb5fd29 x\037nation\037total\037total
#> 3:  total  total d8da72e3fbb5fd29 x\037nation\037total\037total
```
