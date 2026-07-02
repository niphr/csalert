# The settled (eventually-observed) total per reference week

Sums each reference week's counts across all delays up to \`max_delay\`
– the quantity a nowcast is trying to predict – and keeps only weeks old
enough that this total is settled (at least \`max_delay\` weeks before
the triangle's as-of).

## Usage

``` r
nowcast_truth(triangle, max_delay)
```

## Arguments

- triangle:

  A \`csfmt_reporting_triangle_v3\` (single series).

- max_delay:

  Delay horizon in weeks.

## Value

A data.table \`reference\`, \`truth\`.
