# Densify a reporting triangle into per-series reference x delay count matrices

Densify a reporting triangle into per-series reference x delay count
matrices

## Usage

``` r
reporting_triangle_matrix(
  triangle,
  max_delay,
  value_col = attr(triangle, "value_col")
)
```

## Arguments

- triangle:

  A \`csfmt_reporting_triangle_v3\`.

- max_delay:

  Number of delay columns (delay 0 .. max_delay-1, in weeks).

- value_col:

  Which value column to reshape (default the triangle's \`value_col\`;
  pass a denominator column to reshape that instead).

## Value

Named list (by time_series_id) of \`list(reference, mat)\`, where
\`mat\` is a reference x delay count matrix (zeros filled within the
observed region).
