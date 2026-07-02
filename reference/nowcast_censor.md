# Censor a reporting triangle to what was known "as of" a past week

Keeps only cells reported on or before \`as_of\` and rebuilds the
triangle, so its as-of boundary and delay structure are exactly what an
engine would have seen at that week. The basis for replay-based
backtesting.

## Usage

``` r
nowcast_censor(triangle, as_of)
```

## Arguments

- triangle:

  A \`csfmt_reporting_triangle_v3\`.

- as_of:

  An ISO-week string; cells reported after it are dropped.

## Value

A \`csfmt_reporting_triangle_v3\` censored to \`as_of\`.
