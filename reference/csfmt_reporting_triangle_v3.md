# Construct a csfmt_reporting_triangle_v3

Construct a csfmt_reporting_triangle_v3

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

  data.table with identity columns, a reference ISO-week column, a
  reporting date column, and a value column.

- id_cols:

  Identity columns defining a series.

- reference_col:

  ISO-week column name.

- reporting_col:

  Column name holding the calendar date the count was reported. The
  column MUST be a \`Date\`. A character, a number, a factor and an
  \`IDate\` each error. It MUST NOT hold \`NA\`, and a missing value
  errors with its count. One \`NA\` makes \`max()\` return \`NA\`, so
  the as-of boundary would be \`NA\`, no reference week would settle,
  and every nowcast engine would quietly return the observed totals.

- value_col:

  Count column name.

## Value

A validated \`csfmt_reporting_triangle_v3\` (a data.table with the as-of
boundary and column roles stored as attributes). The as-of boundary is a
\`Date\`.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
which builds a triangle with this constructor and takes it through the
whole pipeline.

Other reporting triangle functions:
[`isoyearweek_week_start()`](https://niphr.github.io/csalert/reference/isoyearweek_week_start.md),
[`reporting_triangle_matrix()`](https://niphr.github.io/csalert/reference/reporting_triangle_matrix.md)

## Examples

``` r
# 40 reference weeks, each reported 3, 10 and 17 days after its Monday, then
# right-truncated at one as-of date so the newest weeks are still incomplete
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

# the as-of boundary is the newest reporting date seen
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
