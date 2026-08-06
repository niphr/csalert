# Construct a csfmt_reporting_triangle_v3

Construct a csfmt_reporting_triangle_v3

## Usage

``` r
csfmt_reporting_triangle_v3(
  data,
  id_cols,
  reference_col = "isoyearweek_reference",
  reporting_col = "isoyearweek_reporting",
  value_col = "numerator"
)
```

## Arguments

- data:

  data.table with identity columns, a reference and a reporting ISO-week
  column, and a value column.

- id_cols:

  Identity columns defining a series.

- reference_col, reporting_col:

  ISO-week column names.

- value_col:

  Count column name.

## Value

A validated \`csfmt_reporting_triangle_v3\` (a data.table with the as-of
boundary and column roles stored as attributes).

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
which builds a triangle with this constructor and takes it through the
whole pipeline.

Other reporting triangle functions:
[`reporting_triangle_matrix()`](https://niphr.github.io/csalert/reference/reporting_triangle_matrix.md)

## Examples

``` r
# 40 reference weeks, each reported over delays 0-2, then right-truncated at
# the newest reference week so the most recent weeks are still incomplete
w <- cstime::dates_by_isoyearweek$isoyearweek
i <- match("2023-01", w)
set.seed(1)
d <- data.table::data.table(
  isoyearweek_reference = w[i + rep(0:39, each = 3)],
  isoyearweek_reporting = w[i + rep(0:39, each = 3) + rep(0:2, 40)],
  numerator = rpois(120, c(30, 15, 5)),
  indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
)
d <- d[isoyearweek_reporting <= w[i + 39]]

tri <- csfmt_reporting_triangle_v3(
  d,
  id_cols = c("indicator_tag", "location_code", "age", "sex")
)

# the as-of boundary is the newest reporting week seen
attr(tri, "as_of")
#> [1] "2023-40"
head(tri, 3)
#>    isoyearweek_reference isoyearweek_reporting numerator indicator_tag
#>                   <char>                <char>     <int>        <char>
#> 1:               2023-01               2023-01        26             x
#> 2:               2023-01               2023-02        20             x
#> 3:               2023-01               2023-03         8             x
#>    location_code    age    sex   time_series_id             time_series_label
#>           <char> <char> <char>           <char>                        <char>
#> 1:        nation  total  total d8da72e3fbb5fd29 x\037nation\037total\037total
#> 2:        nation  total  total d8da72e3fbb5fd29 x\037nation\037total\037total
#> 3:        nation  total  total d8da72e3fbb5fd29 x\037nation\037total\037total
```
