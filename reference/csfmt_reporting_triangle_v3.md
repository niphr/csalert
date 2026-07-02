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
