# Week-over-week QC: settled-data integrity (A) + frontier status signal (B)

Week-over-week QC: settled-data integrity (A) + frontier status signal
(B)

## Usage

``` r
qc_week_over_week(current, previous, max_delay, tol = 1e-06)
```

## Arguments

- current, previous:

  Two runs' collapsed csfmt.

- max_delay:

  Nowcast horizon (weeks); sets the settled/frontier boundary.

- tol:

  Tolerance for "unchanged" in the integrity check.

## Value

\`list(integrity = \<A\>, signal = \<B\>)\`.
