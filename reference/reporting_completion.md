# Empirical reporting-completion summary from a reporting triangle

Empirical reporting-completion summary from a reporting triangle

## Usage

``` r
reporting_completion(
  triangle,
  max_delay,
  delay_window = NULL,
  period = c("all", "year", "month")
)
```

## Arguments

- triangle:

  A \`csfmt_reporting_triangle_v3\`.

- max_delay:

  Delay horizon in weeks.

- delay_window:

  Optional: use only settled weeks within roughly this many weeks
  (drift-aware). \`NULL\` uses all settled weeks. Ignored for the shape
  of \`period\` stratification, which slices time itself.

- period:

  Time stratification of the settled weeks, by the calendar year / month
  of each week's Thursday: \`"all"\` (one pooled curve, default),
  \`"year"\`, or \`"month"\` (one row per period). Use
  \`"year"\`/\`"month"\` to see whether completion time is trending up
  or down.

## Value

One row per series (and per period when stratified): identity columns +
\`period\` + \`n_settled\`, \`mean_delay\`, \`complete_by_md\` (fraction
in by \`max_delay\`), and \`pct_w1\`..\`pct_w\<max_delay\>\` (the pooled
% of cases reported after that many weeks observed – the delay ECDF, no
interpolation).
